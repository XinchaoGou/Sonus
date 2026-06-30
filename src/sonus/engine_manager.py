"""Runtime engine switching with single-engine residency."""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass
from typing import Any

from sonus.config import Settings
from sonus.engine_manifest import EngineSpec, load_engine_manifest
from sonus.engines.base import TTSEngine
from sonus.factory import build_engine, build_tts_service
from sonus.model_status import engine_models_ready, missing_engine_model_files
from sonus.service import TTSService

logger = logging.getLogger("sonus.engine_manager")

SWITCH_DRAIN_TIMEOUT_SECONDS = 30.0


class EngineSwitchError(Exception):
    """Raised when engine switch cannot complete."""


@dataclass(frozen=True)
class EngineStatus:
    id: str
    name: str
    active: bool
    installed: bool
    ready: bool
    missing_models: list[str]
    optional_dependency: str | None


class EngineManager:
    """Owns the active engine, TTSService, and hot-switch lifecycle."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._lock = threading.RLock()
        self._cond = threading.Condition(self._lock)
        self._synthesis_count = 0
        self._active_engine_id = settings.engine
        self._engine = build_engine(settings)
        self._tts = self._build_service(self._engine)

    @property
    def settings(self) -> Settings:
        return self._settings

    @property
    def active_engine_id(self) -> str:
        return self._active_engine_id

    @property
    def tts(self) -> TTSService:
        return self._tts

    def begin_synthesis(self) -> None:
        with self._cond:
            self._synthesis_count += 1

    def end_synthesis(self) -> None:
        with self._cond:
            self._synthesis_count = max(0, self._synthesis_count - 1)
            if self._synthesis_count == 0:
                self._cond.notify_all()

    def _build_service(self, engine: TTSEngine) -> TTSService:
        return build_tts_service(
            self._settings,
            engine,
            on_synthesis_start=self.begin_synthesis,
            on_synthesis_end=self.end_synthesis,
        )

    def list_engines(self) -> list[EngineStatus]:
        manifest = load_engine_manifest()
        results: list[EngineStatus] = []
        for engine_id in manifest.list_ids():
            spec = manifest.get(engine_id)
            assert spec is not None
            missing = missing_engine_model_files(engine_id, self._settings)
            ready = engine_models_ready(engine_id, self._settings)
            total_required = _total_required_assets(spec)
            installed = ready or (total_required > 0 and len(missing) < total_required)
            results.append(
                EngineStatus(
                    id=engine_id,
                    name=spec.name,
                    active=engine_id == self._active_engine_id,
                    installed=installed,
                    ready=ready,
                    missing_models=missing,
                    optional_dependency=spec.optional_dependency,
                )
            )
        return results

    def switch_engine(self, engine_id: str, *, timeout: float = SWITCH_DRAIN_TIMEOUT_SECONDS) -> str:
        manifest = load_engine_manifest()
        spec = manifest.get(engine_id)
        if spec is None:
            raise EngineSwitchError(f"Unknown engine: {engine_id!r}")

        with self._cond:
            deadline = time.monotonic() + timeout
            while self._synthesis_count > 0:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise EngineSwitchError(
                        f"Cannot switch engine while {self._synthesis_count} synthesis request(s) are active"
                    )
                self._cond.wait(timeout=remaining)

            if engine_id == self._active_engine_id:
                return self._active_engine_id

            if not engine_models_ready(engine_id, self._settings):
                missing = missing_engine_model_files(engine_id, self._settings)
                raise EngineSwitchError(
                    f"Engine {engine_id!r} is not ready; missing: {', '.join(missing)}"
                )

            _check_optional_dependency(spec)

            logger.info("switching engine %s -> %s", self._active_engine_id, engine_id)
            self._unload_engine(self._engine)

            self._settings.engine = engine_id
            self._active_engine_id = engine_id
            self._engine = build_engine(self._settings)
            self._tts = self._build_service(self._engine)
            logger.info("engine switch complete: %s", engine_id)
            return self._active_engine_id

    @staticmethod
    def _unload_engine(engine: TTSEngine) -> None:
        unload = getattr(engine, "unload", None)
        if callable(unload):
            unload()


def _check_optional_dependency(spec: EngineSpec) -> None:
    if not spec.optional_dependency:
        return
    if spec.optional_dependency == "qwen":
        try:
            import qwen_tts  # noqa: F401
        except ImportError as exc:
            raise EngineSwitchError(
                "Qwen3-TTS requires optional dependencies: uv sync --extra qwen"
            ) from exc


def _total_required_assets(spec: EngineSpec) -> int:
    if spec.assets:
        return len(spec.assets)
    if spec.readiness_files:
        return len(spec.readiness_files)
    return 1


def engine_status_to_dict(status: EngineStatus) -> dict[str, Any]:
    return {
        "id": status.id,
        "name": status.name,
        "active": status.active,
        "installed": status.installed,
        "ready": status.ready,
        "missing_models": status.missing_models,
        "optional_dependency": status.optional_dependency,
    }
