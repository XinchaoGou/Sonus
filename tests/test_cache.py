"""Tests for on-disk audio cache."""

import os
from pathlib import Path

from sonus.cache import AudioCache, build_cache_key


def test_build_cache_key_stable() -> None:
    a = build_cache_key(
        engine_id="kokoro",
        voice="zh_female",
        speed=1.0,
        fmt="wav",
        max_chunk_chars=280,
        text="hello",
    )
    b = build_cache_key(
        engine_id="kokoro",
        voice="zh_female",
        speed=1.0,
        fmt="wav",
        max_chunk_chars=280,
        text="hello",
    )
    assert a == b
    assert len(a) == 64


def test_build_cache_key_changes_with_text() -> None:
    base = dict(engine_id="kokoro", voice="zh_female", speed=1.0, fmt="wav", max_chunk_chars=280)
    assert build_cache_key(text="a", **base) != build_cache_key(text="b", **base)


def test_cache_put_and_get(tmp_path: Path) -> None:
    cache = AudioCache(tmp_path, engine_id="kokoro", enabled=True, ttl_seconds=0)
    payload = b"RIFF...."
    cache.put(
        payload,
        voice="en_female",
        speed=1.0,
        fmt="wav",
        max_chunk_chars=280,
        text="cache me",
    )
    hit = cache.get(
        voice="en_female",
        speed=1.0,
        fmt="wav",
        max_chunk_chars=280,
        text="cache me",
    )
    assert hit == payload


def test_cache_ttl_expiry(tmp_path: Path) -> None:
    cache = AudioCache(tmp_path, engine_id="kokoro", enabled=True, ttl_seconds=1)
    cache.put(b"x", voice="v", speed=1.0, fmt="pcm", max_chunk_chars=0, text="t")
    path = next(tmp_path.rglob("*.pcm"))
    old = path.stat().st_mtime
    os.utime(path, (old - 10, old - 10))
    assert cache.get(voice="v", speed=1.0, fmt="pcm", max_chunk_chars=0, text="t") is None
