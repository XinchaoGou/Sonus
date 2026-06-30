"""Unit tests for OpenAI voice mapping and request schema."""

import pytest
from pydantic import ValidationError

from sonus.openai_compat import OpenAISpeechRequest, resolve_openai_voice


def test_resolve_openai_builtin_voice() -> None:
    assert resolve_openai_voice("alloy", native_voices=set(), engine_id="kokoro") == "en_female"
    assert resolve_openai_voice("onyx", native_voices=set(), engine_id="kokoro") == "en_male"


def test_resolve_openai_logical_voice() -> None:
    assert resolve_openai_voice("zh_female", native_voices=set(), engine_id="kokoro") == "zh_female"


def test_resolve_openai_native_voice() -> None:
    assert resolve_openai_voice("af_bella", native_voices={"af_bella"}, engine_id="kokoro") == "af_bella"


def test_resolve_openai_unknown_voice() -> None:
    with pytest.raises(ValueError, match="Unknown voice"):
        resolve_openai_voice("missing", native_voices=set(), engine_id="kokoro")


def test_openai_request_rejects_unsupported_format() -> None:
    with pytest.raises(ValidationError):
        OpenAISpeechRequest(
            model="tts-1",
            input="hi",
            voice="alloy",
            response_format="flac",
        )
