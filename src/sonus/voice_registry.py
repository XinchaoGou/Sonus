"""Per-engine logical voice mappings (stable API surface)."""

from __future__ import annotations

from sonus.voices import VoiceProfile

KOKORO_LOGICAL: dict[str, VoiceProfile] = {
    "zh_female": VoiceProfile(engine_voice="zf_001", lang="cmn"),
    "zh_male": VoiceProfile(engine_voice="zm_010", lang="cmn"),
    "en_female": VoiceProfile(engine_voice="af_bella", lang="en-us"),
    "en_male": VoiceProfile(engine_voice="am_fenrir", lang="en-us"),
    "ja_female": VoiceProfile(engine_voice="jf_alpha", lang="ja"),
}

QWEN3_LOGICAL: dict[str, VoiceProfile] = {
    "zh_female": VoiceProfile(engine_voice="serena", lang="Chinese"),
    "zh_male": VoiceProfile(engine_voice="uncle_fu", lang="Chinese"),
    "en_female": VoiceProfile(engine_voice="vivian", lang="English"),
    "en_male": VoiceProfile(engine_voice="ryan", lang="English"),
    "ja_female": VoiceProfile(engine_voice="ono_anna", lang="Japanese"),
}

ENGINE_LOGICAL_MAP: dict[str, dict[str, VoiceProfile]] = {
    "kokoro": KOKORO_LOGICAL,
    "qwen3-tts": QWEN3_LOGICAL,
}


def resolve_logical_voice_for_engine(name: str, engine_id: str) -> VoiceProfile | None:
    return ENGINE_LOGICAL_MAP.get(engine_id, {}).get(name)


def list_logical_voices_for_engine(engine_id: str) -> dict[str, VoiceProfile]:
    return dict(ENGINE_LOGICAL_MAP.get(engine_id, {}))
