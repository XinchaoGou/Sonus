"""FastAPI HTTP surface (stable /tts contract)."""

import logging
from contextlib import asynccontextmanager
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import Response, StreamingResponse

from sonus.config import Settings
from sonus.factory import build_engine, build_tts_service
from sonus.logging_config import configure_logging, log_startup
from sonus.middleware import RequestLoggingMiddleware
from sonus.openai_compat import OpenAISpeechRequest, resolve_openai_voice, to_output_format
from sonus.schemas import TTSRequest, TTSStreamRequest
from sonus.service import HEADER_CACHE, TTSService
from sonus.voices import list_logical_voices

logger = logging.getLogger("sonus.tts")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = Settings()
    configure_logging(settings.log_level)
    log_startup(settings)
    engine = build_engine(settings)
    app.state.settings = settings
    app.state.tts = build_tts_service(settings, engine)
    logger.info("TTS engine ready: %s (cache=%s)", settings.engine, settings.cache_enabled)
    yield
    logger.info("Sonus shutting down")


def get_tts(request: Request) -> TTSService:
    return request.app.state.tts


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


app = FastAPI(
    title="Sonus",
    version="0.1.0",
    summary="Local model-agnostic TTS HTTP service",
    lifespan=lifespan,
)
app.add_middleware(RequestLoggingMiddleware)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/voices")
def voices(
    tts: TTSService = Depends(get_tts),
    settings: Settings = Depends(get_settings),
) -> dict[str, Any]:
    """Logical voices (stable) plus native engine ids (informational)."""
    logical = {k: {"engine_voice": v.engine_voice, "lang": v.lang} for k, v in list_logical_voices().items()}
    try:
        native = tts.list_native_voices()
    except FileNotFoundError:
        native = []
    return {"engine": settings.engine, "logical": logical, "native": native}


@app.post("/tts")
def tts_endpoint(body: TTSRequest, tts: TTSService = Depends(get_tts)) -> Response:
    try:
        result = tts.synthesize_bytes(
            text=body.text,
            voice=body.voice,
            speed=body.speed,
            out_format=body.audio_format,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    except RuntimeError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Audio encoding failed: {e}. For MP3, install ffmpeg and ensure it is on PATH.",
        ) from e
    except Exception as e:  # pragma: no cover — defensive
        raise HTTPException(status_code=500, detail=f"TTS failed: {e!s}") from e

    logger.info(
        "synthesized voice=%s format=%s text_chars=%d audio_bytes=%d cache=%s",
        body.voice,
        body.audio_format.value,
        len(body.text),
        len(result.data),
        result.cache,
    )
    return Response(
        content=result.data,
        media_type=result.media_type,
        headers={HEADER_CACHE: result.cache},
    )


@app.post("/tts/stream")
async def tts_stream_endpoint(body: TTSStreamRequest, tts: TTSService = Depends(get_tts)) -> StreamingResponse:
    try:
        cache_status, stream = tts.synthesize_stream_pcm(
            text=body.text, voice=body.voice, speed=body.speed
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e

    async def pcm_chunks():
        total_bytes = 0
        try:
            async for chunk in stream:
                total_bytes += len(chunk)
                yield chunk
        except Exception as e:  # pragma: no cover — defensive
            logger.exception("streaming TTS failed voice=%s", body.voice)
            raise
        logger.info(
            "streamed voice=%s text_chars=%d pcm_bytes=%d cache=%s",
            body.voice,
            len(body.text),
            total_bytes,
            cache_status,
        )

    return StreamingResponse(
        pcm_chunks(),
        media_type=tts.stream_media_type(),
        headers=tts.stream_response_headers(cache=cache_status),
    )


@app.post("/v1/audio/speech")
def openai_speech_endpoint(body: OpenAISpeechRequest, tts: TTSService = Depends(get_tts)) -> Response:
    """OpenAI-compatible text-to-speech (POST /v1/audio/speech)."""
    if body.instructions:
        logger.debug("ignoring OpenAI instructions field (not supported)")
    try:
        voice = resolve_openai_voice(body.voice, native_voices=set(tts.list_native_voices()))
        result = tts.synthesize_bytes(
            text=body.input,
            voice=voice,
            speed=body.speed,
            out_format=to_output_format(body.response_format),
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    except RuntimeError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Audio encoding failed: {e}. For MP3, install ffmpeg and ensure it is on PATH.",
        ) from e
    except Exception as e:  # pragma: no cover — defensive
        raise HTTPException(status_code=500, detail=f"TTS failed: {e!s}") from e

    logger.info(
        "openai speech model=%s voice=%s format=%s input_chars=%d audio_bytes=%d cache=%s",
        body.model,
        body.voice,
        body.response_format.value,
        len(body.input),
        len(result.data),
        result.cache,
    )
    return Response(
        content=result.data,
        media_type=result.media_type,
        headers={HEADER_CACHE: result.cache},
    )
