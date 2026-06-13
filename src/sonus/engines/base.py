"""Model-agnostic TTS engine interface."""

from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Protocol, runtime_checkable

import numpy as np


@dataclass(frozen=True)
class SynthesisResult:
    """Raw audio from an engine (float32 samples)."""

    samples: np.ndarray
    sample_rate: int


@runtime_checkable
class TTSEngine(Protocol):
    """Pluggable backend. Implementations must be thread-safe after init."""

    engine_id: str

    def synthesize(
        self,
        text: str,
        *,
        voice: str,
        speed: float,
        lang: str,
    ) -> SynthesisResult:
        """Generate speech for plain text."""
        ...

    def list_voices(self) -> list[str]:
        """Return native voice ids supported by this engine."""
        ...


@runtime_checkable
class StreamingTTSEngine(TTSEngine, Protocol):
    """Engine that can yield audio incrementally (optional capability)."""

    def synthesize_stream(
        self,
        text: str,
        *,
        voice: str,
        speed: float,
        lang: str,
    ) -> AsyncIterator[SynthesisResult]:
        """Async-generate speech fragments for one text segment."""
        ...
