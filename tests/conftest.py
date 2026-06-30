"""Shared test fixtures."""

from __future__ import annotations

from collections.abc import AsyncIterator

import numpy as np
import pytest
from fastapi.testclient import TestClient

from sonus.app import app
from sonus.config import Settings
from sonus.engines.base import SynthesisResult
from sonus.service import TTSService


class MockEngine:
    """In-memory TTS engine for unit/API tests (no ONNX models)."""

    engine_id = "kokoro"

    def __init__(self, voices: list[str] | None = None) -> None:
        self.voices = voices or ["af_bella", "zf_001", "am_fenrir"]
        self.calls: list[dict[str, object]] = []

    def synthesize(
        self,
        text: str,
        *,
        voice: str,
        speed: float,
        lang: str,
    ) -> SynthesisResult:
        self.calls.append({"text": text, "voice": voice, "speed": speed, "lang": lang, "mode": "sync"})
        samples = np.zeros(2400, dtype=np.float32)
        return SynthesisResult(samples=samples, sample_rate=24000)

    async def synthesize_stream(
        self,
        text: str,
        *,
        voice: str,
        speed: float,
        lang: str,
    ) -> AsyncIterator[SynthesisResult]:
        self.calls.append({"text": text, "voice": voice, "speed": speed, "lang": lang, "mode": "stream"})
        for _ in range(2):
            yield SynthesisResult(samples=np.zeros(1200, dtype=np.float32), sample_rate=24000)

    def list_voices(self) -> list[str]:
        return list(self.voices)

    def unload(self) -> None:
        pass


@pytest.fixture
def mock_engine() -> MockEngine:
    return MockEngine()


@pytest.fixture
def mock_tts(mock_engine: MockEngine) -> TTSService:
    return TTSService(mock_engine, engine_id=mock_engine.engine_id)


@pytest.fixture
def api_client(mock_engine: MockEngine, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    monkeypatch.setattr("sonus.engine_manager.build_engine", lambda settings: mock_engine)
    with TestClient(app) as client:
        manager = client.app.state.engine_manager
        manager._tts = TTSService(mock_engine, engine_id=mock_engine.engine_id, cache=None)
        client.app.state.tts = manager.tts
        yield client
