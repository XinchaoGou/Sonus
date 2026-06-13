"""Tests for TTSService orchestration with a mock engine."""

from pathlib import Path

import pytest

from sonus.cache import AudioCache
from sonus.schemas import AudioFormat
from sonus.service import TTSService
from conftest import MockEngine


def test_synthesize_logical_voice_maps_engine(mock_tts: TTSService, mock_engine: MockEngine) -> None:
    result = mock_tts.synthesize_bytes(
        text="你好",
        voice="zh_female",
        speed=1.0,
        out_format=AudioFormat.wav,
    )
    assert result.media_type == "audio/wav"
    assert result.data[:4] == b"RIFF"
    assert result.cache == "disabled"
    assert len(mock_engine.calls) == 1
    call = mock_engine.calls[0]
    assert call["voice"] == "zf_001"
    assert call["lang"] == "cmn"
    assert call["text"] == "你好"


def test_synthesize_native_voice(mock_tts: TTSService, mock_engine: MockEngine) -> None:
    mock_tts.synthesize_bytes(
        text="Hello",
        voice="af_bella",
        speed=1.1,
        out_format=AudioFormat.wav,
    )
    call = mock_engine.calls[0]
    assert call["voice"] == "af_bella"
    assert call["lang"] == "en-us"
    assert call["speed"] == 1.1


def test_synthesize_unknown_native_voice_raises(mock_tts: TTSService) -> None:
    with pytest.raises(ValueError, match="Unknown voice"):
        mock_tts.synthesize_bytes(
            text="Hello",
            voice="does_not_exist",
            speed=1.0,
            out_format=AudioFormat.wav,
        )


def test_list_native_voices(mock_tts: TTSService) -> None:
    assert "af_bella" in mock_tts.list_native_voices()


def test_synthesize_long_text_uses_multiple_chunks(mock_engine: MockEngine) -> None:
    tts = TTSService(mock_engine, max_chunk_chars=12)
    text = "这是第一句。这是第二句。这是第三句。"
    result = tts.synthesize_bytes(
        text=text,
        voice="zh_female",
        speed=1.0,
        out_format=AudioFormat.wav,
    )
    assert result.media_type == "audio/wav"
    assert result.data[:4] == b"RIFF"
    assert len(mock_engine.calls) >= 2
    assert all(call["voice"] == "zf_001" for call in mock_engine.calls)


def test_synthesize_cache_hit_skips_engine(tmp_path: Path, mock_engine: MockEngine) -> None:
    cache = AudioCache(tmp_path, engine_id="mock", enabled=True)
    tts = TTSService(mock_engine, cache=cache)
    first = tts.synthesize_bytes(
        text="cached phrase",
        voice="en_female",
        speed=1.0,
        out_format=AudioFormat.wav,
    )
    assert first.cache == "miss"
    assert len(mock_engine.calls) == 1

    second = tts.synthesize_bytes(
        text="cached phrase",
        voice="en_female",
        speed=1.0,
        out_format=AudioFormat.wav,
    )
    assert second.cache == "hit"
    assert second.data == first.data
    assert len(mock_engine.calls) == 1
