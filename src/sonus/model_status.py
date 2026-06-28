"""Model file readiness checks for /health and startup."""

from __future__ import annotations

from sonus.config import Settings


def missing_model_files(settings: Settings) -> list[str]:
    """Return paths of required Kokoro model files that are missing."""
    required = [
        settings.resolve_model_path(),
        settings.resolve_voices_path(),
        settings.resolve_zh_model_path(),
        settings.resolve_zh_voices_path(),
        settings.resolve_zh_vocab_config_path(),
    ]
    return [str(path) for path in required if not path.is_file()]


def models_ready(settings: Settings) -> bool:
    return not missing_model_files(settings)
