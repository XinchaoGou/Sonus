"""OpenAI Audio API (/v1/audio/speech) compatibility layer."""

from __future__ import annotations

from enum import Enum
from typing import Annotated, Literal

from pydantic import BaseModel, Field, field_validator

from sonus.engine_manifest import load_engine_manifest
from sonus.voices import list_logical_voices, resolve_logical_voice

# Map OpenAI built-in voice ids to Sonus logical voices (stable HTTP surface).
OPENAI_VOICE_MAP: dict[str, str] = {
    "alloy": "en_female",
    "ash": "en_male",
    "ballad": "en_male",
    "cedar": "en_male",
    "coral": "en_female",
    "echo": "en_male",
    "fable": "en_male",
    "marin": "en_female",
    "nova": "en_female",
    "onyx": "en_male",
    "sage": "en_female",
    "shimmer": "en_female",
    "verse": "en_male",
}

SUPPORTED_RESPONSE_FORMATS = frozenset({"mp3", "wav", "pcm"})
OutputFormat = Literal["mp3", "wav", "pcm"]


class OpenAIResponseFormat(str, Enum):
    mp3 = "mp3"
    wav = "wav"
    pcm = "pcm"
    opus = "opus"
    aac = "aac"
    flac = "flac"


class OpenAISpeechRequest(BaseModel):
    """Body for POST /v1/audio/speech (OpenAI Audio API compatible)."""

    model: Annotated[str, Field(min_length=1)]
    input: Annotated[str, Field(min_length=1, max_length=4096)]
    voice: Annotated[str, Field(min_length=1)]
    response_format: OpenAIResponseFormat = OpenAIResponseFormat.mp3
    speed: float = Field(default=1.0, ge=0.25, le=4.0)
    instructions: str | None = None

    @field_validator("input")
    @classmethod
    def strip_input(cls, v: str) -> str:
        s = v.strip()
        if not s:
            raise ValueError("input must not be empty or whitespace-only")
        return s

    @field_validator("response_format")
    @classmethod
    def supported_response_format(cls, v: OpenAIResponseFormat) -> OpenAIResponseFormat:
        if v.value not in SUPPORTED_RESPONSE_FORMATS:
            raise ValueError(
                f"response_format {v.value!r} is not supported by Sonus; use mp3, wav, or pcm"
            )
        return v


def resolve_openai_model(model: str) -> str:
    """Map OpenAI model id (or alias) to a Sonus engine id."""
    normalized = model.strip().lower()
    manifest = load_engine_manifest()
    for engine_id, spec in manifest.engines.items():
        if normalized == engine_id.lower():
            return engine_id
        if normalized in {alias.lower() for alias in spec.openai_model_aliases}:
            return engine_id
    raise ValueError(
        f"Unknown model {model!r}. Use an active engine id ({', '.join(manifest.list_ids())}) "
        "or a supported OpenAI alias (e.g. tts-1)."
    )


def resolve_openai_voice(voice: str, *, native_voices: set[str], engine_id: str) -> str:
    """Map OpenAI voice id (or Sonus logical / native id) to a Sonus voice id."""
    mapped = OPENAI_VOICE_MAP.get(voice)
    if mapped is not None:
        return mapped
    if resolve_logical_voice(voice, engine_id) is not None:
        return voice
    if voice in native_voices:
        return voice
    known = sorted(OPENAI_VOICE_MAP.keys())
    logical = sorted(list_logical_voices(engine_id).keys())
    raise ValueError(
        f"Unknown voice {voice!r}. Use an OpenAI voice ({', '.join(known[:6])}, …), "
        f"a logical id ({', '.join(logical)}), or a native engine voice."
    )


def to_output_format(response_format: OpenAIResponseFormat) -> OutputFormat:
    return response_format.value  # type: ignore[return-value]
