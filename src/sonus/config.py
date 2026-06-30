"""Application configuration (env + defaults)."""

from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings. Override via environment variables with prefix SONUS_."""

    model_config = SettingsConfigDict(
        env_prefix="SONUS_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    host: str = Field(default="127.0.0.1", description="Bind address for HTTP server")
    port: int = Field(default=8000, ge=1, le=65535, description="Bind port")

    engine: str = Field(default="kokoro", description="Active TTS engine id")

    model_path: Path = Field(
        default=Path("models/kokoro-v1.0.onnx"),
        description="Path to Kokoro v1.0 ONNX model (multilingual, non-Chinese G2P)",
    )
    voices_path: Path = Field(
        default=Path("models/voices-v1.0.bin"),
        description="Path to Kokoro v1.0 voices bundle",
    )

    zh_model_path: Path = Field(
        default=Path("models/kokoro-v1.1-zh.onnx"),
        description="Path to Kokoro v1.1 Chinese ONNX model",
    )
    zh_voices_path: Path = Field(
        default=Path("models/voices-v1.1-zh.bin"),
        description="Path to Kokoro v1.1 Chinese voices bundle",
    )
    zh_vocab_config_path: Path = Field(
        default=Path("models/kokoro-v1.1-zh-config.json"),
        description="Path to Kokoro v1.1 Chinese vocab config.json",
    )

    models_dir: Path | None = Field(
        default=None,
        description="When set, default model filenames resolve under this directory",
    )

    log_level: str = Field(
        default="info",
        description="Log level: debug, info, warning, error, critical",
    )

    max_chunk_chars: int = Field(
        default=280,
        ge=0,
        description="Max characters per TTS chunk (0 = no splitting)",
    )

    cache_enabled: bool = Field(default=True, description="Enable on-disk audio cache")
    cache_dir: Path = Field(
        default=Path(".cache/sonus"),
        description="Directory for cached audio files",
    )
    cache_ttl_seconds: int = Field(
        default=0,
        ge=0,
        description="Cache entry TTL in seconds (0 = never expire by age)",
    )

    zh_en_mixed: bool = Field(
        default=True,
        description="Use misaki en_callable for English segments in Chinese text",
    )

    qwen3_model_dir: Path = Field(
        default=Path("models/qwen3-tts"),
        description="Directory containing Qwen3-TTS CustomVoice Hugging Face snapshot",
    )

    engine_switch_timeout_seconds: float = Field(
        default=30.0,
        ge=1.0,
        description="Max seconds to wait for in-flight synthesis before engine switch fails",
    )

    def resolve_models_dir(self) -> Path | None:
        if self.models_dir is None:
            return None
        return self.models_dir.expanduser().resolve()

    def _resolve_path(self, field_path: Path, filename: str) -> Path:
        models_dir = self.resolve_models_dir()
        if models_dir is not None:
            return models_dir / filename
        return field_path.expanduser().resolve()

    def resolve_model_path(self) -> Path:
        return self._resolve_path(self.model_path, "kokoro-v1.0.onnx")

    def resolve_voices_path(self) -> Path:
        return self._resolve_path(self.voices_path, "voices-v1.0.bin")

    def resolve_zh_model_path(self) -> Path:
        return self._resolve_path(self.zh_model_path, "kokoro-v1.1-zh.onnx")

    def resolve_zh_voices_path(self) -> Path:
        return self._resolve_path(self.zh_voices_path, "voices-v1.1-zh.bin")

    def resolve_zh_vocab_config_path(self) -> Path:
        return self._resolve_path(self.zh_vocab_config_path, "kokoro-v1.1-zh-config.json")

    def resolve_qwen3_model_dir(self) -> Path:
        models_dir = self.resolve_models_dir()
        if models_dir is not None:
            return (models_dir / "qwen3-tts").resolve()
        return self.qwen3_model_dir.expanduser().resolve()

    def resolve_cache_dir(self) -> Path:
        return self.cache_dir.expanduser().resolve()
