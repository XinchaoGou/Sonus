"""Model-agnostic synthesis orchestration."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import AsyncIterator

import numpy as np

from sonus.audio_encode import (
    HEADER_AUDIO_FORMAT,
    HEADER_AUDIO_SAMPLE_RATE,
    PCM_FORMAT_NAME,
    STREAM_PCM_MEDIA_TYPE,
    encode_audio,
    float32_to_pcm_s16le,
)
from sonus.cache import AudioCache, CacheStatus, EncodedAudio
from sonus.engines.base import SynthesisResult, StreamingTTSEngine, TTSEngine
from sonus.openai_compat import OutputFormat
from sonus.schemas import AudioFormat
from sonus.text_split import split_text
from sonus.voices import infer_lang_for_engine_voice, resolve_logical_voice

logger = logging.getLogger("sonus.tts")

HEADER_CACHE = "X-Cache"
STREAM_CHUNK_BYTES = 8192


class TTSService:
    """Maps API-level voice ids to engine voices and encodes audio."""

    def __init__(
        self,
        engine: TTSEngine,
        *,
        engine_id: str | None = None,
        max_chunk_chars: int = 280,
        cache: AudioCache | None = None,
        on_synthesis_start=None,
        on_synthesis_end=None,
    ) -> None:
        self._engine = engine
        self._engine_id = engine_id or engine.engine_id
        self._max_chunk_chars = max_chunk_chars
        self._cache = cache
        self._on_synthesis_start = on_synthesis_start
        self._on_synthesis_end = on_synthesis_end

    @property
    def engine_id(self) -> str:
        return self._engine_id

    def list_native_voices(self) -> list[str]:
        return self._engine.list_voices()

    def _synthesis_scope(self):
        if self._on_synthesis_start is None and self._on_synthesis_end is None:
            from contextlib import nullcontext

            return nullcontext()
        from contextlib import contextmanager

        @contextmanager
        def _scope():
            if self._on_synthesis_start is not None:
                self._on_synthesis_start()
            try:
                yield
            finally:
                if self._on_synthesis_end is not None:
                    self._on_synthesis_end()

        return _scope()

    def synthesize_bytes(
        self,
        *,
        text: str,
        voice: str,
        speed: float,
        out_format: AudioFormat | OutputFormat,
    ) -> EncodedAudio:
        fmt = out_format.value if isinstance(out_format, AudioFormat) else out_format
        if self._cache is not None:
            cached = self._cache.get(
                voice=voice,
                speed=speed,
                fmt=fmt,
                max_chunk_chars=self._max_chunk_chars,
                text=text,
            )
            if cached is not None:
                logger.info(
                    "cache hit voice=%s format=%s text_chars=%d audio_bytes=%d",
                    voice,
                    fmt,
                    len(text),
                    len(cached),
                )
                media_type = {
                    "wav": "audio/wav",
                    "mp3": "audio/mpeg",
                    "pcm": "application/octet-stream",
                }[fmt]
                return EncodedAudio(data=cached, media_type=media_type, cache="hit")

        with self._synthesis_scope():
            engine_voice, lang = self._resolve_voice(voice)
            chunks = split_text(text, self._max_chunk_chars)
            if not chunks:
                raise ValueError("text must not be empty or whitespace-only")

            if len(chunks) == 1:
                result = self._engine.synthesize(chunks[0], voice=engine_voice, speed=speed, lang=lang)
            else:
                logger.info(
                    "long text split into %d chunks (max_chunk_chars=%d, total_chars=%d)",
                    len(chunks),
                    self._max_chunk_chars,
                    len(text),
                )
                result = self._synthesize_chunks(chunks, engine_voice=engine_voice, speed=speed, lang=lang)

            payload, media_type = encode_audio(
                np.asarray(result.samples, dtype=np.float32),
                result.sample_rate,
                fmt,
            )
            cache_status: CacheStatus = "disabled"
            if self._cache is not None:
                self._cache.put(
                    payload,
                    voice=voice,
                    speed=speed,
                    fmt=fmt,
                    max_chunk_chars=self._max_chunk_chars,
                    text=text,
                )
                cache_status = "miss"

        return EncodedAudio(data=payload, media_type=media_type, cache=cache_status)

    def _resolve_voice(self, voice: str) -> tuple[str, str]:
        profile = resolve_logical_voice(voice, self._engine_id)
        if profile is not None:
            return profile.engine_voice, profile.lang

        engine_voice = voice
        lang = infer_lang_for_engine_voice(engine_voice)
        native = set(self._engine.list_voices())
        if engine_voice not in native:
            raise ValueError(
                f"Unknown voice {voice!r}. "
                f"Use a logical id (see GET /voices) or a native engine voice."
            )
        return engine_voice, lang

    def _synthesize_chunks(
        self,
        chunks: list[str],
        *,
        engine_voice: str,
        speed: float,
        lang: str,
    ) -> SynthesisResult:
        parts: list[np.ndarray] = []
        sample_rate: int | None = None
        for chunk in chunks:
            part = self._engine.synthesize(chunk, voice=engine_voice, speed=speed, lang=lang)
            if sample_rate is None:
                sample_rate = part.sample_rate
            elif part.sample_rate != sample_rate:
                raise RuntimeError(
                    f"Inconsistent sample rates across chunks: {sample_rate} vs {part.sample_rate}"
                )
            parts.append(np.asarray(part.samples, dtype=np.float32))
        assert sample_rate is not None
        return SynthesisResult(samples=np.concatenate(parts), sample_rate=sample_rate)

    def synthesize_stream_pcm(
        self,
        *,
        text: str,
        voice: str,
        speed: float,
    ) -> tuple[CacheStatus, AsyncIterator[bytes]]:
        """Return cache status and an async PCM chunk iterator."""
        if self._cache is not None:
            cached = self._cache.get(
                voice=voice,
                speed=speed,
                fmt="pcm",
                max_chunk_chars=self._max_chunk_chars,
                text=text,
            )
            if cached is not None:
                logger.info(
                    "stream cache hit voice=%s text_chars=%d pcm_bytes=%d",
                    voice,
                    len(text),
                    len(cached),
                )

                async def cached_chunks() -> AsyncIterator[bytes]:
                    for offset in range(0, len(cached), STREAM_CHUNK_BYTES):
                        yield cached[offset : offset + STREAM_CHUNK_BYTES]

                return "hit", cached_chunks()

        cache_status: CacheStatus = "miss" if self._cache is not None else "disabled"

        async def live_chunks() -> AsyncIterator[bytes]:
            if self._on_synthesis_start is not None:
                self._on_synthesis_start()
            try:
                buffer = bytearray()
                async for chunk in self._synthesize_stream_pcm_uncached(text=text, voice=voice, speed=speed):
                    buffer.extend(chunk)
                    yield chunk
                if self._cache is not None and buffer:
                    self._cache.put(
                        bytes(buffer),
                        voice=voice,
                        speed=speed,
                        fmt="pcm",
                        max_chunk_chars=self._max_chunk_chars,
                        text=text,
                    )
            finally:
                if self._on_synthesis_end is not None:
                    self._on_synthesis_end()

        return cache_status, live_chunks()

    async def _synthesize_stream_pcm_uncached(
        self,
        *,
        text: str,
        voice: str,
        speed: float,
    ) -> AsyncIterator[bytes]:
        engine_voice, lang = self._resolve_voice(voice)
        chunks = split_text(text, self._max_chunk_chars)
        if not chunks:
            raise ValueError("text must not be empty or whitespace-only")

        if len(chunks) > 1:
            logger.info(
                "streaming long text split into %d chunks (max_chunk_chars=%d, total_chars=%d)",
                len(chunks),
                self._max_chunk_chars,
                len(text),
            )

        if isinstance(self._engine, StreamingTTSEngine):
            for chunk in chunks:
                async for part in self._engine.synthesize_stream(
                    chunk, voice=engine_voice, speed=speed, lang=lang
                ):
                    if part.samples.size:
                        yield float32_to_pcm_s16le(part.samples)
            return

        if len(chunks) == 1:
            result = await asyncio.to_thread(
                self._engine.synthesize,
                chunks[0],
                voice=engine_voice,
                speed=speed,
                lang=lang,
            )
        else:
            result = await asyncio.to_thread(
                self._synthesize_chunks,
                chunks,
                engine_voice=engine_voice,
                speed=speed,
                lang=lang,
            )
        if result.samples.size:
            yield float32_to_pcm_s16le(result.samples)

    @staticmethod
    def stream_response_headers(sample_rate: int = 24000, *, cache: CacheStatus = "disabled") -> dict[str, str]:
        headers = {
            HEADER_AUDIO_SAMPLE_RATE: str(sample_rate),
            HEADER_AUDIO_FORMAT: PCM_FORMAT_NAME,
            HEADER_CACHE: cache,
        }
        return headers

    @staticmethod
    def stream_media_type() -> str:
        return STREAM_PCM_MEDIA_TYPE
