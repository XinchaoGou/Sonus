"""Per-engine model readiness checks."""

from __future__ import annotations

from sonus.config import Settings
from sonus.engine_manifest import load_engine_manifest


def missing_kokoro_model_files(settings: Settings) -> list[str]:
    required = [
        settings.resolve_model_path(),
        settings.resolve_voices_path(),
        settings.resolve_zh_model_path(),
        settings.resolve_zh_voices_path(),
        settings.resolve_zh_vocab_config_path(),
    ]
    return [str(path) for path in required if not path.is_file()]


def missing_qwen3_model_files(settings: Settings) -> list[str]:
    model_dir = settings.resolve_qwen3_model_dir()
    missing: list[str] = []
    if not model_dir.is_dir():
        missing.append(str(model_dir))
        return missing
    for filename in ("config.json",):
        path = model_dir / filename
        if not path.is_file():
            missing.append(str(path))
    weight_candidates = (
        "model.safetensors",
        "pytorch_model.bin",
        "model.safetensors.index.json",
    )
    if not any((model_dir / name).is_file() for name in weight_candidates):
        missing.append(str(model_dir / "model.safetensors"))
    return missing


_ENGINE_MISSING_CHECKERS = {
    "kokoro": missing_kokoro_model_files,
    "qwen3-tts": missing_qwen3_model_files,
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
