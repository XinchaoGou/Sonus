"""Chinese G2P helpers (Kokoro v1.1-zh + misaki ZHG2P)."""

from __future__ import annotations

from typing import Any, Callable


def phonemes_from_g2p_result(result: object) -> str:
    """Normalize misaki G2P return values to a phoneme string.

    ``en.G2P`` and ``EspeakG2P`` return ``(phonemes, meta)`` but ``ZHG2P``
    historically appended the raw tuple; unwrap here so mixed zh/en text works.
    """
    if isinstance(result, (tuple, list)):
        if not result:
            return ""
        return str(result[0])
    return str(result)


def build_en_callable(*, british: bool = False) -> Callable[[str], str]:
    """English segment phonemizer for ``ZHG2P(en_callable=...)``.

    Uses misaki ``EspeakG2P`` (espeak-ng via phonemizer). No spacy/torch required.
    """
    from misaki import espeak

    language = "en-gb" if british else "en-us"
    en_g2p = espeak.EspeakG2P(language)

    def en_callable(text: str) -> str:
        return phonemes_from_g2p_result(en_g2p(text))

    return en_callable


def build_zh_g2p(*, en_mixed: bool = True, british_en: bool = False) -> Any:
    """Construct misaki ``ZHG2P`` for Kokoro v1.1-zh."""
    from misaki import zh as misaki_zh

    en_callable = build_en_callable(british=british_en) if en_mixed else None
    return misaki_zh.ZHG2P(version="1.1", en_callable=en_callable)
