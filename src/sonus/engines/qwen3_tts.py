"""Qwen3-TTS CustomVoice engine (optional qwen-tts + PyTorch)."""

from __future__ import annotations

import logging
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


class Qwen3TTSEngine:
    """Qwen3-TTS CustomVoice via official ``qwen-tts`` package."""

    engine_id = "qwen3-tts"

    def __init__(self, model_dir: Path) -> None:
        self._model_dir = model_dir
        self._model = None

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

        if torch.backends.mps.is_available():
            device_map = "mps"
            dtype = torch.float32
        elif torch.cuda.is_available():
            device_map = "cuda:0"
            dtype = torch.bfloat16
        else:
            device_map = "cpu"
            dtype = torch.float32

        logger.info("loading Qwen3-TTS from %s (device=%s)", self._model_dir, device_map)
        self._model = Qwen3TTSModel.from_pretrained(
            str(self._model_dir),
            device_map=device_map,
            dtype=dtype,
        )
        return self._model

    def unload(self) -> None:
        self._model = None

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
        wavs, sample_rate = model.generate_custom_voice(
            text=text,
            speaker=speaker,
            language=language,
            non_streaming_mode=True,
        )
        samples = np.asarray(wavs[0], dtype=np.float32)
        return SynthesisResult(samples=samples, sample_rate=int(sample_rate))

    def list_voices(self) -> list[str]:
        return list(_NATIVE_SPEAKERS)
