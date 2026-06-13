"""Logical voice ids (API-stable) mapped to engine-specific voices and phonemizer language."""

import re
from dataclasses import dataclass

# Kokoro v1.1-zh voices use numeric suffixes (e.g. zf_001); v1.0 uses names (e.g. zf_xiaoxiao).
_V1_1_ZH_VOICE = re.compile(r"^(zf|zm)_\d+$")

CMN_LANGS = frozenset({"cmn", "zh", "zh-cn", "zh_cn"})


@dataclass(frozen=True)
class VoiceProfile:
    """How a logical voice is realized on the current backend."""

    engine_voice: str
    lang: str


# Logical names are the stable surface for clients; backend ids may change when swapping engines.
_LOGICAL: dict[str, VoiceProfile] = {
    "zh_female": VoiceProfile(engine_voice="zf_001", lang="cmn"),
    "zh_male": VoiceProfile(engine_voice="zm_010", lang="cmn"),
    "en_female": VoiceProfile(engine_voice="af_bella", lang="en-us"),
    "en_male": VoiceProfile(engine_voice="am_fenrir", lang="en-us"),
    "ja_female": VoiceProfile(engine_voice="jf_alpha", lang="ja"),
}


def resolve_logical_voice(name: str) -> VoiceProfile | None:
    return _LOGICAL.get(name)


def list_logical_voices() -> dict[str, VoiceProfile]:
    return dict(_LOGICAL)


def is_cmn_lang(lang: str) -> bool:
    return lang.lower() in CMN_LANGS


def is_zh_v1_1_voice(voice: str) -> bool:
    return bool(_V1_1_ZH_VOICE.match(voice))


def should_use_zh_stack(*, lang: str, voice: str) -> bool:
    """Route to Kokoro v1.1-zh + misaki G2P (not espeak cmn)."""
    return is_cmn_lang(lang) or is_zh_v1_1_voice(voice)


def infer_lang_for_engine_voice(engine_voice: str) -> str:
    """Best-effort language tag from Kokoro voice id."""
    if len(engine_voice) < 2:
        return "en-us"
    prefix2 = engine_voice[:2].lower()
    if prefix2 in ("zf", "zm"):
        return "cmn"
    if prefix2 in ("jf", "jm"):
        return "ja"
    if prefix2 in ("bf", "bm"):
        return "en-gb"
    if prefix2 in ("ef", "em"):
        return "es"
    if prefix2 in ("ff",):
        return "fr-fr"
    if prefix2 in ("hf", "hm"):
        return "hi"
    if prefix2 in ("if", "im"):
        return "it"
    if prefix2 in ("pf", "pm"):
        return "pt-br"
    return "en-us"
