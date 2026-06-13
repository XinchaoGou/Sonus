"""Tests for PCM encoding helpers."""

import numpy as np

from sonus.audio_encode import float32_to_pcm_s16le


def test_float32_to_pcm_s16le() -> None:
    samples = np.array([0.0, 1.0, -1.0], dtype=np.float32)
    raw = float32_to_pcm_s16le(samples)
    assert len(raw) == 6
    assert raw[2:4] == (32767).to_bytes(2, "little", signed=True)
