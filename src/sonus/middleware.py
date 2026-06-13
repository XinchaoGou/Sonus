"""HTTP middleware for request tracing."""

from __future__ import annotations

import logging
import time

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from sonus.logging_config import REQUEST_ID_HEADER, new_request_id, request_id_ctx

logger = logging.getLogger("sonus.http")


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Assign/propagate request id and log request lifecycle."""

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        request_id = new_request_id(request.headers.get(REQUEST_ID_HEADER))
        request.state.request_id = request_id
        token = request_id_ctx.set(request_id)

        start = time.perf_counter()
        logger.info("%s %s", request.method, request.url.path)
        try:
            response = await call_next(request)
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.info(
                "%s %s -> %s (%.1fms)",
                request.method,
                request.url.path,
                response.status_code,
                elapsed_ms,
            )
            response.headers[REQUEST_ID_HEADER] = request_id
            return response
        except Exception:
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.exception("%s %s failed after %.1fms", request.method, request.url.path, elapsed_ms)
            raise
        finally:
            request_id_ctx.reset(token)
