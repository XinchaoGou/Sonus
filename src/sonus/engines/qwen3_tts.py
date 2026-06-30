"""Qwen3-TTS CustomVoice engine (optional qwen-tts + PyTorch)."""

from __future__ import annotations

import gc
import logging
import os
from pathlib import Path

import numpy as np

from sonus.engines.base import SynthesisResult

logger = logging.getLogger("sonus.engines.qwen3_tts")

_NATIVE_SPEAKERS = (
    "aiden",
    "dylan",
    "eric",
    "ono_anna",
    "ryan",
    "serena",
    "sohee",
    "uncle_fu",
    "vivian",
)


def _resolve_device() -> str:
    """Pick the torch device for Qwen3-TTS.

    ``SONUS_QWEN_DEVICE`` overrides auto-detection (one of ``cpu`` / ``mps`` /
    ``cuda`` / ``auto``). MPS is notoriously unstable for this model, so users
    who hit runtime crashes can force ``cpu`` without code changes.
    """
    override = os.environ.get("SONUS_QWEN_DEVICE", "").strip().lower()
    if override and override != "auto":
        return override
    try:
        import torch

        if torch.backends.mps.is_available():
            return "mps"
        if torch.cuda.is_available():
            return "cuda:0"
    except ImportError:
        pass
    return "cpu"


class Qwen3TTSEngine:
    """Qwen3-TTS CustomVoice via official ``qwen-tts`` package."""

    engine_id = "qwen3-tts"

    def __init__(self, model_dir: Path) -> None:
        self._model_dir = model_dir
        self._model = None
        self._device: str | None = None

    def _ensure_loaded(self):
        if self._model is not None:
            return self._model

        if not self._model_dir.is_dir():
            raise FileNotFoundError(
                f"Qwen3-TTS model directory not found: {self._model_dir}. "
                "Run scripts/download-qwen3-model.sh or set SONUS_QWEN3_MODEL_DIR."
            )
        config_path = self._model_dir / "config.json"
        if not config_path.is_file():
            raise FileNotFoundError(
                f"Qwen3-TTS config.json not found in {self._model_dir}. "
                "Download the Hugging Face model snapshot first."
            )

        try:
            import torch
            from qwen_tts import Qwen3TTSModel
        except ImportError as exc:  # pragma: no cover - optional extra
            raise RuntimeError(
                "Qwen3-TTS requires the optional dependency group: uv sync --extra qwen"
            ) from exc

        device_map = _resolve_device()
        dtype = torch.bfloat16 if device_map.startswith("cuda") else torch.float32

        logger.info("loading Qwen3-TTS from %s (device=%s)", self._model_dir, device_map)
        try:
            self._model = Qwen3TTSModel.from_pretrained(
                str(self._model_dir),
                device_map=device_map,
                dtype=dtype,
            )
            self._device = device_map
        except Exception as exc:
            if device_map == "mps":
                logger.warning(
                    "Qwen3-TTS MPS load failed (%s); falling back to CPU",
                    exc,
                )
                self._model = Qwen3TTSModel.from_pretrained(
                    str(self._model_dir),
                    device_map="cpu",
                    dtype=torch.float32,
                )
                self._device = "cpu"
            else:
                raise
        return self._model

    def _reload_on_cpu(self) -> None:
        """Drop the current model and reload it on CPU (MPS runtime fallback)."""
        logger.warning("Qwen3-TTS reloading model on CPU after MPS runtime failure")
        self.unload()
        import torch
        from qwen_tts import Qwen3TTSModel

        self._model = Qwen3TTSModel.from_pretrained(
            str(self._model_dir),
            device_map="cpu",
            dtype=torch.float32,
        )
        self._device = "cpu"

    def unload(self) -> None:
        # Move tensors off the accelerator before dropping the reference so the
        # MPS/CUDA allocator can actually reclaim memory during hot-switch.
        if self._model is not None:
            try:
                self._model.to("cpu")
            except Exception:
                pass
        self._model = None
        self._device = None
        gc.collect()
        try:
            import torch

            if torch.backends.mps.is_available():
                if hasattr(torch.mps, "synchronize"):
                    torch.mps.synchronize()
                torch.mps.empty_cache()
            elif torch.cuda.is_available():
                torch.cuda.empty_cache()
        except ImportError:
            pass

    def synthesize(
        self,
        text: str,
        *,
        voice: str,
        speed: float,
        lang: str,
    ) -> SynthesisResult:
        if speed != 1.0:
            logger.debug("qwen3-tts ignores speed=%s (not supported)", speed)

        model = self._ensure_loaded()
        speaker = voice.lower()
        language = lang or "Auto"
        try:
            wavs, sample_rate = model.generate_custom_voice(
                text=text,
                speaker=speaker,
                language=language,
                non_streaming_mode=True,
            )
        except Exception as exc:
            # MPS often fails at inference time (OOM, allocator, graph errors)
            # even when from_pretrained succeeded. Retry once on CPU instead of
            # propagating a crash that takes down the whole backend process.
            if self._device == "mps":
                logger.warning(
                    "Qwen3-TTS MPS generate failed (%s); retrying on CPU", exc
                )
                self._reload_on_cpu()
                model = self._model
                wavs, sample_rate = model.generate_custom_voice(
                    text=text,
                    speaker=speaker,
                    language=language,
                    non_streaming_mode=True,
                )
            else:
                raise
        samples = np.asarray(wavs[0], dtype=np.float32)
        return SynthesisResult(samples=samples, sample_rate=int(sample_rate))

    def list_voices(self) -> list[str]:
        return list(_NATIVE_SPEAKERS)
