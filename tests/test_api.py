"""HTTP API tests with mock TTS engine (no model files)."""

from fastapi.testclient import TestClient

from sonus.audio_encode import HEADER_AUDIO_FORMAT, HEADER_AUDIO_SAMPLE_RATE
from sonus.logging_config import REQUEST_ID_HEADER
from conftest import MockEngine


def test_health(api_client: TestClient) -> None:
    response = api_client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] in {"ok", "degraded"}
    assert "models_ready" in body
    assert isinstance(body["models_ready"], bool)


def test_voices_includes_logical_and_native(api_client: TestClient, mock_engine: MockEngine) -> None:
    response = api_client.get("/voices")
    assert response.status_code == 200
    body = response.json()
    assert body["engine"] == "kokoro"
    assert "zh_female" in body["logical"]
    assert body["logical"]["zh_female"]["engine_voice"] == "zf_001"
    assert "af_bella" in body["native"]
    assert "af_bella" in mock_engine.voices


def test_tts_returns_wav(api_client: TestClient, mock_engine: MockEngine) -> None:
    response = api_client.post(
        "/tts",
        json={"text": "测试", "voice": "en_female", "speed": 1.0, "format": "wav"},
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/wav"
    assert response.content[:4] == b"RIFF"
    assert mock_engine.calls[0]["voice"] == "af_bella"


def test_tts_unknown_voice_400(api_client: TestClient) -> None:
    response = api_client.post(
        "/tts",
        json={"text": "hi", "voice": "unknown_voice", "speed": 1.0, "format": "wav"},
    )
    assert response.status_code == 400
    assert "Unknown voice" in response.json()["detail"]


def test_request_id_header_echoed(api_client: TestClient) -> None:
    response = api_client.get("/health", headers={REQUEST_ID_HEADER: "pytest-req-1"})
    assert response.status_code == 200
    assert response.headers[REQUEST_ID_HEADER] == "pytest-req-1"


def test_request_id_generated_when_missing(api_client: TestClient) -> None:
    response = api_client.get("/health")
    rid = response.headers.get(REQUEST_ID_HEADER)
    assert rid
    assert len(rid) >= 8


def test_tts_stream_returns_pcm(api_client: TestClient, mock_engine: MockEngine) -> None:
    with api_client.stream(
        "POST",
        "/tts/stream",
        json={"text": "stream test", "voice": "en_female", "speed": 1.0},
    ) as response:
        assert response.status_code == 200
        assert response.headers[HEADER_AUDIO_SAMPLE_RATE] == "24000"
        assert response.headers[HEADER_AUDIO_FORMAT] == "pcm_s16le"
        assert "audio/L16" in response.headers["content-type"]
        payload = b"".join(response.iter_bytes())
    assert len(payload) > 0
    assert len(payload) % 2 == 0
    assert mock_engine.calls[0]["mode"] == "stream"

