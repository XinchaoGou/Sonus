"""Tests for logical voice mapping and language routing helpers."""

import pytest

from sonus.voices import (
    infer_lang_for_engine_voice,
    is_cmn_lang,
    is_zh_v1_1_voice,
    resolve_logical_voice,
    should_use_zh_stack,
)


def test_resolve_logical_zh_female() -> None:
    profile = resolve_logical_voice("zh_female")
    assert profile is not None
    assert profile.engine_voice == "zf_001"
    assert profile.lang == "cmn"


def test_resolve_logical_unknown() -> None:
    assert resolve_logical_voice("not_a_voice") is None


@pytest.mark.parametrize(
    ("voice", "lang"),
    [
        ("zf_001", "cmn"),
        ("zf_xiaoxiao", "cmn"),
        ("af_bella", "en-us"),
        ("bf_emma", "en-gb"),
        ("jf_alpha", "ja"),
    ],
)
def test_infer_lang_for_engine_voice(voice: str, lang: str) -> None:
    assert infer_lang_for_engine_voice(voice) == lang


@pytest.mark.parametrize("lang", ["cmn", "zh", "zh-CN", "zh_cn"])
def test_is_cmn_lang(lang: str) -> None:
    assert is_cmn_lang(lang)


def test_is_zh_v1_1_voice() -> None:
    assert is_zh_v1_1_voice("zf_001")
    assert is_zh_v1_1_voice("zm_100")
    assert not is_zh_v1_1_voice("zf_xiaoxiao")


def test_should_use_zh_stack() -> None:
    assert should_use_zh_stack(lang="cmn", voice="af_bella")
    assert should_use_zh_stack(lang="en-us", voice="zf_042")
    assert not should_use_zh_stack(lang="en-us", voice="af_bella")
