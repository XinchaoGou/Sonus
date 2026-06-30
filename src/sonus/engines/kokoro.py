"""Kokoro ONNX engine (phase-1 default)."""

from __future__ import annotations

import gc
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Any

import numpy as np
from kokoro_onnx import Kokoro

from sonus.engines.base import SynthesisResult
from sonus.voices import should_use_zh_stack
from sonus.zh_g2p import build_zh_g2p


class KokoroEngine:
    """Kokoro via kokoro-onnx + ONNX Runtime.

    - Non-Chinese (and legacy v1.0 voices): kokoro-v1.0 + espeak/phonemizer ``lang``.
    - Mandarin: kokoro-v1.1-zh + misaki ``ZHG2P`` (+ optional ``en_callable`` for zh/en mix).
    """

    engine_id = "kokoro"

    def __init__(
        self,
        model_path: Path,
        voices_path: Path,
        *,
        zh_model_path: Path,
        zh_voices_path: Path,
        zh_vocab_config_path: Path,
        zh_en_mixed: bool = True,
    ) -> None:
        self._model_path = model_path
        self._voices_path = voices_path
        self._zh_model_path = zh_model_path
        self._zh_voices_path = zh_voices_path
        self._zh_vocab_config_path = zh_vocab_config_path
        self._zh_en_mixed = zh_en_mixed
        self._kokoro_v1: Kokoro | None = None
        self._kokoro_zh: Kokoro | None = None
        self._zh_g2p: Any = None

    def _ensure_v1_loaded(self) -> Kokoro:
        if self._kokoro_v1 is None:
            if not self._model_path.is_file():
                raise FileNotFoundError(
                    f"Kokoro v1.0 model not found: {self._model_path}. "
                    "Download kokoro-v1.0.onnx (see README)."
                )
            if not self._voices_path.is_file():
                raise FileNotFoundError(
                    f"Kokoro v1.0 voices not found: {self._voices_path}. "
                    "Download voices-v1.0.bin (see README)."
                )
            self._kokoro_v1 = Kokoro(str(self._model_path), str(self._voices_path))
        return self._kokoro_v1

    def _ensure_zh_loaded(self) -> Kokoro:
        if self._kokoro_zh is None:
            if not self._zh_model_path.is_file():
                raise FileNotFoundError(
                    f"Kokoro v1.1 Chinese model not found: {self._zh_model_path}. "
                    "Download kokoro-v1.1-zh.onnx (see README)."
                )
            if not self._zh_voices_path.is_file():
                raise FileNotFoundError(
                    f"Kokoro v1.1 Chinese voices not found: {self._zh_voices_path}. "
                    "Download voices-v1.1-zh.bin (see README)."
                )
            if not self._zh_vocab_config_path.is_file():
                raise FileNotFoundError(
                    f"Kokoro v1.1 Chinese vocab config not found: {self._zh_vocab_config_path}. "
                    "Download kokoro-v1.1-zh-config.json (see README)."
                )
            self._kokoro_zh = Kokoro(
                str(self._zh_model_path),
                str(self._zh_voices_path),
                vocab_config=str(self._zh_vocab_config_path),
            )
        return self._kokoro_zh

    def _ensure_zh_g2p(self) -> Any:
        if self._zh_g2p is None:
            self._zh_g2p = build_zh_g2p(en_mixed=self._zh_en_mixed)
        return self._zh_g2p

    def synthesize(
        self,
        text: str,
        *,
        voice: str,
        speed: float,
        lang: str,
    ) -> SynthesisResult:
        if should_use_zh_stack(lang=lang, voice=voice):
            k = self._ensure_zh_loaded()
            phonemes, _ = self._ensure_zh_g2p()(text)
            samples, sample_rate = k.create(
                phonemes, voice=voice, speed=speed, is_phonemes=True
            )
        else:
            k = self._ensure_v1_loaded()
            samples, sample_rate = k.create(text, voice=voice, speed=speed, lang=lang)
        return SynthesisResult(
            samples=np.asarray(samples, dtype=np.float32),
            sample_rate=int(sample_rate),
        )

    async def synthesize_stream(
        self,
        text: str,
        *,
        voice: str,
        speed: float,
        lang: str,
    ) -> AsyncIterator[SynthesisResult]:
        if should_use_zh_stack(lang=lang, voice=voice):
            k = self._ensure_zh_loaded()
            phonemes, _ = self._ensure_zh_g2p()(text)
            stream = k.create_stream(phonemes, voice=voice, speed=speed, is_phonemes=True)
        else:
            k = self._ensure_v1_loaded()
            stream = k.create_stream(text, voice=voice, speed=speed, lang=lang)

        async for samples, sample_rate in stream:
            yield SynthesisResult(
                samples=np.asarray(samples, dtype=np.float32),
                sample_rate=int(sample_rate),
            )

    def list_voices(self) -> list[str]:
        voices: set[str] = set()
        try:
            voices.update(self._ensure_v1_loaded().get_voices())
        except FileNotFoundError:
            pass
        try:
            voices.update(self._ensure_zh_loaded().get_voices())
        except FileNotFoundError:
            pass
        if not voices:
            raise FileNotFoundError(
                "No Kokoro model files found. Download v1.0 and/or v1.1-zh assets (see README)."
            )
        return sorted(voices)

    def unload(self) -> None:
        self._kokoro_v1 = None
        self._kokoro_zh = None
        self._zh_g2p = None
        gc.collect()
