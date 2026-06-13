"""Tests for HTTP request schema validation."""

import pytest
from pydantic import ValidationError

from sonus.schemas import AudioFormat, TTSRequest


def test_tts_request_defaults() -> None:
    req = TTSRequest(text="hello")
    assert req.voice == "zh_female"
    assert req.speed == 1.0
    assert req.audio_format == AudioFormat.wav


def test_tts_request_format_alias() -> None:
    req = TTSRequest.model_validate({"text": "hello", "format": "mp3"})
    assert req.audio_format == AudioFormat.mp3


def test_tts_request_strips_text() -> None:
    req = TTSRequest(text="  hello  ")
    assert req.text == "hello"


def test_tts_request_rejects_blank_text() -> None:
    with pytest.raises(ValidationError):
        TTSRequest(text="   ")


def test_tts_request_speed_bounds() -> None:
    with pytest.raises(ValidationError):
        TTSRequest(text="hi", speed=0.4)
