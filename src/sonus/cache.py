"""On-disk audio cache keyed by synthesis parameters."""

from __future__ import annotations

import hashlib
import json
import logging
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

logger = logging.getLogger("sonus.cache")

CacheStatus = Literal["hit", "miss", "disabled"]

_CACHE_VERSION = 1
_FORMAT_EXT = {
    "wav": ".wav",
    "mp3": ".mp3",
    "pcm": ".pcm",
}


@dataclass(frozen=True)
class EncodedAudio:
    """Encoded audio bytes plus cache metadata for HTTP headers."""

    data: bytes
    media_type: str
    cache: CacheStatus


def build_cache_key(
    *,
    engine_id: str,
    voice: str,
    speed: float,
    fmt: str,
    max_chunk_chars: int,
    text: str,
) -> str:
    """Stable sha256 hex digest for a synthesis request."""
    payload = {
        "v": _CACHE_VERSION,
        "engine": engine_id,
        "voice": voice,
        "speed": round(speed, 3),
        "format": fmt,
        "max_chunk_chars": max_chunk_chars,
        "text": text.strip(),
    }
    canonical = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


class AudioCache:
    """Filesystem cache for encoded audio (WAV / MP3 / PCM)."""

    def __init__(
        self,
        cache_dir: Path,
        *,
        engine_id: str,
        enabled: bool = True,
        ttl_seconds: int = 0,
    ) -> None:
        self._cache_dir = cache_dir
        self._engine_id = engine_id
        self._enabled = enabled
        self._ttl_seconds = max(0, ttl_seconds)

    @classmethod
    def from_settings(cls, settings, *, engine_id: str) -> AudioCache:
        return cls(
            settings.resolve_cache_dir(),
            engine_id=engine_id,
            enabled=settings.cache_enabled,
            ttl_seconds=settings.cache_ttl_seconds,
        )

    @property
    def enabled(self) -> bool:
        return self._enabled

    def _path_for(self, key: str, fmt: str) -> Path:
        ext = _FORMAT_EXT[fmt]
        return self._cache_dir / key[:2] / f"{key}{ext}"

    def get(
        self,
        *,
        voice: str,
        speed: float,
        fmt: str,
        max_chunk_chars: int,
        text: str,
    ) -> bytes | None:
        if not self._enabled:
            return None
        key = build_cache_key(
            engine_id=self._engine_id,
            voice=voice,
            speed=speed,
            fmt=fmt,
            max_chunk_chars=max_chunk_chars,
            text=text,
        )
        path = self._path_for(key, fmt)
        if not path.is_file():
            return None
        if self._is_expired(path):
            try:
                path.unlink(missing_ok=True)
            except OSError:
                logger.warning("failed to remove expired cache file %s", path)
            return None
        data = path.read_bytes()
        logger.debug("cache hit key=%s bytes=%d", key[:12], len(data))
        return data

    def put(
        self,
        data: bytes,
        *,
        voice: str,
        speed: float,
        fmt: str,
        max_chunk_chars: int,
        text: str,
    ) -> None:
        if not self._enabled or not data:
            return
        key = build_cache_key(
            engine_id=self._engine_id,
            voice=voice,
            speed=speed,
            fmt=fmt,
            max_chunk_chars=max_chunk_chars,
            text=text,
        )
        path = self._path_for(key, fmt)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_bytes(data)
        tmp.replace(path)
        logger.debug("cache store key=%s bytes=%d path=%s", key[:12], len(data), path)

    def _is_expired(self, path: Path) -> bool:
        if self._ttl_seconds <= 0:
            return False
        age = time.time() - path.stat().st_mtime
        return age > self._ttl_seconds
