"""HTTP request / response models (stable public contract)."""

from enum import Enum
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, field_validator


class AudioFormat(str, Enum):
    wav = "wav"
    mp3 = "mp3"


class TTSRequest(BaseModel):
    """Body for POST /tts."""

    model_config = ConfigDict(populate_by_name=True)

    text: Annotated[str, Field(min_length=1, max_length=50_000)]
    voice: str = Field(
        default="zh_female",
        description="Logical voice id (e.g. zh_female) or raw engine voice id (e.g. zf_xiaoxiao)",
    )
    speed: float = Field(default=1.0, ge=0.5, le=2.0)
    audio_format: AudioFormat = Field(
        default=AudioFormat.wav,
        alias="format",
        description="Output container: wav (default) or mp3 (requires ffmpeg for encoding)",
    )

    @field_validator("text")
    @classmethod
    def strip_text(cls, v: str) -> str:
        s = v.strip()
        if not s:
            raise ValueError("text must not be empty or whitespace-only")
        return s


class SetActiveEngineRequest(BaseModel):
    """Body for PUT /engines/active."""

    engine: Annotated[str, Field(min_length=1, description="Engine id from GET /engines")]


class TTSStreamRequest(BaseModel):
    """Body for POST /tts/stream (PCM chunks only)."""

    text: Annotated[str, Field(min_length=1, max_length=50_000)]
    voice: str = Field(
        default="zh_female",
        description="Logical voice id (e.g. zh_female) or raw engine voice id",
    )
    speed: float = Field(default=1.0, ge=0.5, le=2.0)

    @field_validator("text")
    @classmethod
    def strip_text(cls, v: str) -> str:
        s = v.strip()
        if not s:
            raise ValueError("text must not be empty or whitespace-only")
        return s
