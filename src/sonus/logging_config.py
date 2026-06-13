"""Application logging: level config, request id context, startup helpers."""

from __future__ import annotations

import logging
import sys
import uuid
from contextvars import ContextVar
from typing import Final

from sonus import __version__
from sonus.config import Settings

REQUEST_ID_HEADER: Final = "X-Request-ID"

request_id_ctx: ContextVar[str] = ContextVar("request_id", default="-")

_LOG_LEVELS = frozenset({"debug", "info", "warning", "error", "critical"})


class RequestIdFilter(logging.Filter):
    """Inject request id from context into log records."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_ctx.get("-")  # type: ignore[attr-defined]
        return True


def normalize_log_level(level: str) -> str:
    normalized = level.strip().lower()
    if normalized not in _LOG_LEVELS:
        raise ValueError(f"Invalid log level {level!r}; use one of: {', '.join(sorted(_LOG_LEVELS))}")
    return normalized


def configure_logging(level: str = "info") -> str:
    """Configure root + uvicorn loggers. Returns normalized level name."""
    normalized = normalize_log_level(level)
    log_level = getattr(logging, normalized.upper())

    handler = logging.StreamHandler(sys.stderr)
    handler.addFilter(RequestIdFilter())
    handler.setFormatter(
        logging.Formatter(
            fmt="%(asctime)s %(levelname)s [%(name)s] [req=%(request_id)s] %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
    )

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(log_level)

    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        uv_logger = logging.getLogger(name)
        uv_logger.handlers.clear()
        uv_logger.propagate = True
        uv_logger.setLevel(log_level)

    return normalized


def new_request_id(incoming: str | None = None) -> str:
    """Reuse client request id or generate a new UUID."""
    if incoming and incoming.strip():
        return incoming.strip()[:128]
    return str(uuid.uuid4())


def log_startup(settings: Settings) -> None:
    """Log process configuration once at startup."""
    logger = logging.getLogger("sonus.startup")
    logger.info(
        "Sonus v%s starting engine=%s log_level=%s",
        __version__,
        settings.engine,
        settings.log_level,
    )
    logger.info("HTTP bind (default): %s:%s", settings.host, settings.port)
    _log_model_path(logger, "v1.0", settings.resolve_model_path(), settings.resolve_voices_path())
    _log_model_path(
        logger,
        "v1.1-zh",
        settings.resolve_zh_model_path(),
        settings.resolve_zh_voices_path(),
        extra=settings.resolve_zh_vocab_config_path(),
    )
    logger.info("Chinese zh/en mixed G2P: %s", settings.zh_en_mixed)


def _log_model_path(
    logger: logging.Logger,
    label: str,
    model_path,
    voices_path,
    *,
    extra=None,
) -> None:
    model_ok = model_path.is_file()
    voices_ok = voices_path.is_file()
    extra_ok = extra.is_file() if extra is not None else True
    ready = model_ok and voices_ok and extra_ok
    logger.info(
        "Model %s ready=%s model=%s voices=%s",
        label,
        ready,
        model_path,
        voices_path,
    )
    if extra is not None:
        logger.info("Model %s vocab=%s exists=%s", label, extra, extra_ok)
