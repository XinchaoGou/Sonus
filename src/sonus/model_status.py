"""Per-engine model readiness checks."""

from __future__ import annotations

from sonus.config import Settings


def missing_kokoro_model_files(settings: Settings) -> list[str]:
    required = [
        settings.resolve_model_path(),
        settings.resolve_voices_path(),
        settings.resolve_zh_model_path(),
        settings.resolve_zh_voices_path(),
        settings.resolve_zh_vocab_config_path(),
    ]
    return [str(path) for path in required if not path.is_file()]


_ENGINE_MISSING_CHECKERS = {
    "kokoro": missing_kokoro_model_files,
}


def missing_engine_model_files(engine_id: str, settings: Settings) -> list[str]:
    checker = _ENGINE_MISSING_CHECKERS.get(engine_id)
    if checker is None:
        return [f"unknown engine: {engine_id}"]
    return checker(settings)


def engine_models_ready(engine_id: str, settings: Settings) -> bool:
    return not missing_engine_model_files(engine_id, settings)


def missing_model_files(settings: Settings) -> list[str]:
    """Missing files for the active engine (health probe)."""
    return missing_engine_model_files(settings.engine, settings)


def models_ready(settings: Settings) -> bool:
    return engine_models_ready(settings.engine, settings)
