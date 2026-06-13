"""Wire settings to concrete engines and services."""

from sonus.cache import AudioCache
from sonus.config import Settings
from sonus.engines.base import TTSEngine
from sonus.engines.kokoro import KokoroEngine
from sonus.service import TTSService


def build_engine(settings: Settings) -> TTSEngine:
    """Construct the active TTS engine from settings."""
    if settings.engine == "kokoro":
        return KokoroEngine(
            settings.resolve_model_path(),
            settings.resolve_voices_path(),
            zh_model_path=settings.resolve_zh_model_path(),
            zh_voices_path=settings.resolve_zh_voices_path(),
            zh_vocab_config_path=settings.resolve_zh_vocab_config_path(),
            zh_en_mixed=settings.zh_en_mixed,
        )
    raise ValueError(f"Unsupported SONUS_ENGINE: {settings.engine!r}")


def build_cache(settings: Settings) -> AudioCache | None:
    if not settings.cache_enabled:
        return None
    return AudioCache.from_settings(settings, engine_id=settings.engine)


def build_tts_service(settings: Settings, engine: TTSEngine) -> TTSService:
    return TTSService(
        engine,
        max_chunk_chars=settings.max_chunk_chars,
        cache=build_cache(settings),
    )
