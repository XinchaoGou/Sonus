"""Encode float32 PCM to WAV / MP3 / raw PCM bytes."""

import io
from typing import Literal

import numpy as np
import soundfile as sf

STREAM_PCM_MEDIA_TYPE = "audio/L16; rate=24000; channels=1"
HEADER_AUDIO_SAMPLE_RATE = "X-Audio-Sample-Rate"
HEADER_AUDIO_FORMAT = "X-Audio-Format"
PCM_FORMAT_NAME = "pcm_s16le"


def float32_to_pcm_s16le(samples: np.ndarray) -> bytes:
    """Convert mono float32 [-1, 1] to little-endian int16 bytes."""
    pcm = np.clip(np.asarray(samples, dtype=np.float32), -1.0, 1.0)
    int16 = (pcm * 32767.0).astype(np.int16)
    return int16.tobytes()


def encode_wav(samples: np.ndarray, sample_rate: int) -> bytes:
    """Write mono float32 samples to 16-bit PCM WAV in memory."""
    buf = io.BytesIO()
    # soundfile expects shape (frames,) or (frames, channels)
    pcm = np.clip(samples.astype(np.float32), -1.0, 1.0)
    sf.write(buf, pcm, sample_rate, format="WAV", subtype="PCM_16")
    return buf.getvalue()


def encode_mp3_from_wav(wav_bytes: bytes) -> bytes:
    """Transcode WAV bytes to MP3 using pydub (requires ffmpeg binary on PATH)."""
    try:
        from pydub import AudioSegment
    except ImportError as e:  # pragma: no cover
        raise RuntimeError("pydub is required for MP3 output") from e

    seg = AudioSegment.from_wav(io.BytesIO(wav_bytes))
    out = io.BytesIO()
    seg.export(out, format="mp3")
    data = out.getvalue()
    if not data:
        raise RuntimeError("MP3 export produced empty output; is ffmpeg installed?")
    return data


def encode_pcm_raw(samples: np.ndarray) -> bytes:
    """Raw 16-bit signed little-endian mono PCM (OpenAI pcm format, no WAV header)."""
    return float32_to_pcm_s16le(samples)


def encode_audio(
    samples: np.ndarray,
    sample_rate: int,
    fmt: Literal["wav", "mp3", "pcm"],
) -> tuple[bytes, str]:
    """Return (payload, media_type)."""
    if fmt == "pcm":
        return encode_pcm_raw(samples), "application/octet-stream"
    wav = encode_wav(samples, sample_rate)
    if fmt == "wav":
        return wav, "audio/wav"
    mp3 = encode_mp3_from_wav(wav)
    return mp3, "audio/mpeg"
