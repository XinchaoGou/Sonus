"""Wire settings to concrete engines and services."""

from sonus.cache import AudioCache
from sonus.config import Settings
from sonus.engines.base import TTSEngine
from sonus.engines.kokoro import KokoroEngine
from sonus.engines.qwen3_tts import Qwen3TTSEngine
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
    if settings.engine == "qwen3-tts":
        return Qwen3TTSEngine(settings.resolve_qwen3_model_dir())
    raise ValueError(f"Unsupported SONUS_ENGINE: {settings.engine!r}")


def build_cache(settings: Settings, *, engine_id: str) -> AudioCache | None:
    if not settings.cache_enabled:
        return None
    return AudioCache.from_settings(settings, engine_id=engine_id)


def build_tts_service(
    settings: Settings,
    engine: TTSEngine,
    *,
    on_synthesis_start=None,
    on_synthesis_end=None,
) -> TTSService:
    return TTSService(
        engine,
        engine_id=engine.engine_id,
        max_chunk_chars=settings.max_chunk_chars,
        cache=build_cache(settings, engine_id=engine.engine_id),
        on_synthesis_start=on_synthesis_start,
        on_synthesis_end=on_synthesis_end,
    )
