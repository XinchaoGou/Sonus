"""Tests for streaming PCM synthesis."""

import asyncio
from pathlib import Path

import pytest

from sonus.cache import AudioCache
from sonus.service import TTSService
from conftest import MockEngine


@pytest.mark.asyncio
async def test_synthesize_stream_pcm_yields_multiple_chunks(mock_engine: MockEngine) -> None:
    tts = TTSService(mock_engine)
    cache_status, stream = tts.synthesize_stream_pcm(text="hello", voice="en_female", speed=1.0)
    assert cache_status == "disabled"
    chunks: list[bytes] = []
    async for pcm in stream:
        chunks.append(pcm)
    assert len(chunks) == 2
    assert all(len(c) % 2 == 0 for c in chunks)
    assert mock_engine.calls[0]["mode"] == "stream"
    assert mock_engine.calls[0]["voice"] == "af_bella"


def test_synthesize_stream_pcm_unknown_voice(mock_engine: MockEngine) -> None:
    tts = TTSService(mock_engine)

    async def run() -> None:
        _status, stream = tts.synthesize_stream_pcm(text="hi", voice="nope", speed=1.0)
        async for _ in stream:
            pass

    with pytest.raises(ValueError, match="Unknown voice"):
        asyncio.run(run())


@pytest.mark.asyncio
async def test_stream_cache_hit(tmp_path: Path, mock_engine: MockEngine) -> None:
    cache = AudioCache(tmp_path, engine_id="mock", enabled=True)
    tts = TTSService(mock_engine, cache=cache)

    status1, stream1 = tts.synthesize_stream_pcm(text="stream cache", voice="en_female", speed=1.0)
    assert status1 == "miss"
    first = b"".join([c async for c in stream1])
    assert len(mock_engine.calls) == 1

    status2, stream2 = tts.synthesize_stream_pcm(text="stream cache", voice="en_female", speed=1.0)
    assert status2 == "hit"
    second = b"".join([c async for c in stream2])
    assert second == first
    assert len(mock_engine.calls) == 1
