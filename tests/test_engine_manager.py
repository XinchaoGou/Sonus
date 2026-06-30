"""Engine manager and /engines API tests."""

from __future__ import annotations

from pathlib import Path

import pytest

from sonus.config import Settings
from sonus.engine_manager import EngineManager, EngineSwitchError
from conftest import MockEngine


@pytest.fixture
def kokoro_ready_settings(tmp_path: Path) -> Settings:
    for name in (
        "kokoro-v1.0.onnx",
        "voices-v1.0.bin",
        "kokoro-v1.1-zh.onnx",
        "voices-v1.1-zh.bin",
        "kokoro-v1.1-zh-config.json",
    ):
        (tmp_path / name).write_bytes(b"x")
    return Settings(models_dir=tmp_path, engine="kokoro")


def test_list_engines_endpoint(api_client) -> None:
    response = api_client.get("/engines")
    assert response.status_code == 200
    body = response.json()
    ids = {item["id"] for item in body}
    assert "kokoro" in ids
    assert "qwen3-tts" not in ids


def test_health_includes_engine(api_client) -> None:
    response = api_client.get("/health")
    assert response.status_code == 200
    assert "engine" in response.json()


def test_switch_engine_rejects_unknown(api_client) -> None:
    response = api_client.put("/engines/active", json={"engine": "unknown"})
    assert response.status_code == 400


def test_switch_engine_rejects_busy(kokoro_ready_settings: Settings, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("sonus.factory.build_engine", lambda settings: MockEngine())
    manager = EngineManager(kokoro_ready_settings)
    manager.begin_synthesis()
    try:
        with pytest.raises(EngineSwitchError, match="synthesis"):
            manager.switch_engine("kokoro", timeout=0.1)
    finally:
        manager.end_synthesis()


def test_engine_manager_rebuilds_cache_engine_id(kokoro_ready_settings: Settings, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("sonus.factory.build_engine", lambda settings: MockEngine())
    manager = EngineManager(kokoro_ready_settings)
    assert manager.tts.engine_id == "kokoro"


def test_settings_falls_back_removed_engine(kokoro_ready_settings: Settings) -> None:
    settings = Settings(**{**kokoro_ready_settings.model_dump(), "engine": "qwen3-tts"})
    assert settings.engine == "kokoro"


def test_engine_manager_starts_with_removed_engine(
    kokoro_ready_settings: Settings, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = kokoro_ready_settings.model_copy(update={"engine": "qwen3-tts"})
    monkeypatch.setattr("sonus.factory.build_engine", lambda s: MockEngine())
    manager = EngineManager(settings)
    assert manager.active_engine_id == "kokoro"
    assert settings.engine == "kokoro"
