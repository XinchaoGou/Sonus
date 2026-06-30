"""FastAPI HTTP surface (stable /tts contract)."""

import logging
from contextlib import asynccontextmanager
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import Response, StreamingResponse

from sonus.config import Settings
from sonus.engine_manager import EngineManager, EngineSwitchError, engine_status_to_dict
from sonus.logging_config import configure_logging, log_startup
from sonus.middleware import RequestLoggingMiddleware
from sonus.model_status import missing_model_files, models_ready
from sonus.openai_compat import (
    OpenAISpeechRequest,
    resolve_openai_model,
    resolve_openai_voice,
    to_output_format,
)
from sonus.schemas import SetActiveEngineRequest, TTSRequest, TTSStreamRequest
from sonus.service import HEADER_CACHE, TTSService
from sonus.voices import list_logical_voices

logger = logging.getLogger("sonus.tts")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = Settings()
    configure_logging(settings.log_level)
    log_startup(settings)
    engine_manager = EngineManager(settings)
    app.state.settings = settings
    app.state.engine_manager = engine_manager
    app.state.tts = engine_manager.tts
    logger.info(
        "TTS engine ready: %s (cache=%s)",
        engine_manager.active_engine_id,
        settings.cache_enabled,
    )
    yield
    logger.info("Sonus shutting down")


def get_engine_manager(request: Request) -> EngineManager:
    return request.app.state.engine_manager


def get_tts(request: Request) -> TTSService:
    return request.app.state.engine_manager.tts


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
def health(
    settings: Settings = Depends(get_settings),
    engine_manager: EngineManager = Depends(get_engine_manager),
) -> dict[str, str | bool | list[str]]:
    """Liveness probe; includes model file readiness for embedded clients."""
    ready = models_ready(settings)
    payload: dict[str, str | bool | list[str]] = {
        "status": "ok" if ready else "degraded",
        "engine": engine_manager.active_engine_id,
        "models_ready": ready,
    }
    if not ready:
        payload["missing_models"] = missing_model_files(settings)
    return payload


@app.get("/engines")
def list_engines(engine_manager: EngineManager = Depends(get_engine_manager)) -> list[dict[str, Any]]:
    """List registered engines with install/ready state."""
    return [engine_status_to_dict(status) for status in engine_manager.list_engines()]


@app.put("/engines/active")
def set_active_engine(
    body: SetActiveEngineRequest,
    request: Request,
    engine_manager: EngineManager = Depends(get_engine_manager),
) -> dict[str, str]:
    """Hot-switch the active TTS engine (single-engine residency)."""
    try:
        active = engine_manager.switch_engine(
            body.engine,
            timeout=engine_manager.settings.engine_switch_timeout_seconds,
        )
    except EngineSwitchError as exc:
        message = str(exc)
        if "synthesis request" in message:
            raise HTTPException(status_code=409, detail=message) from exc
        if "not ready" in message or "requires optional" in message:
            raise HTTPException(status_code=503, detail=message) from exc
        raise HTTPException(status_code=400, detail=message) from exc

    request.app.state.tts = engine_manager.tts
    engine_manager.settings.engine = active
    return {"engine": active}


@app.get("/voices")
def voices(
    tts: TTSService = Depends(get_tts),
    engine_manager: EngineManager = Depends(get_engine_manager),
) -> dict[str, Any]:
    """Logical voices (stable) plus native engine ids (informational)."""
    engine_id = engine_manager.active_engine_id
    logical = {
        k: {"engine_voice": v.engine_voice, "lang": v.lang}
        for k, v in list_logical_voices(engine_id).items()
    }
    try:
        native = tts.list_native_voices()
    except FileNotFoundError:
        native = []
    return {"engine": engine_id, "logical": logical, "native": native}


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
        except Exception:  # pragma: no cover — defensive
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
def openai_speech_endpoint(
    body: OpenAISpeechRequest,
    tts: TTSService = Depends(get_tts),
    engine_manager: EngineManager = Depends(get_engine_manager),
) -> Response:
    """OpenAI-compatible text-to-speech (POST /v1/audio/speech)."""
    if body.instructions:
        logger.debug("ignoring OpenAI instructions field (not supported)")
    try:
        resolved_model = resolve_openai_model(body.model)
        if resolved_model != engine_manager.active_engine_id:
            raise ValueError(
                f"model {body.model!r} does not match active engine "
                f"{engine_manager.active_engine_id!r}"
            )
        voice = resolve_openai_voice(
            body.voice,
            native_voices=set(tts.list_native_voices()),
            engine_id=engine_manager.active_engine_id,
        )
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
