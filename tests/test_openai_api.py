"""OpenAI-compatible /v1/audio/speech API tests."""

from fastapi.testclient import TestClient

from conftest import MockEngine
from sonus.service import HEADER_CACHE


def test_openai_speech_default_mp3(api_client: TestClient, mock_engine: MockEngine) -> None:
    response = api_client.post(
        "/v1/audio/speech",
        json={
            "model": "tts-1",
            "input": "Hello from OpenAI compat",
            "voice": "alloy",
        },
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/mpeg"
    assert len(response.content) > 0
    assert mock_engine.calls[0]["voice"] == "af_bella"
    assert mock_engine.calls[0]["text"] == "Hello from OpenAI compat"


def test_openai_speech_wav(api_client: TestClient) -> None:
    response = api_client.post(
        "/v1/audio/speech",
        json={
            "model": "tts-1",
            "input": "WAV test",
            "voice": "nova",
            "response_format": "wav",
        },
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/wav"
    assert response.content[:4] == b"RIFF"


def test_openai_speech_pcm(api_client: TestClient) -> None:
    response = api_client.post(
        "/v1/audio/speech",
        json={
            "model": "tts-1-hd",
            "input": "PCM test",
            "voice": "echo",
            "response_format": "pcm",
        },
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/octet-stream"
    assert len(response.content) % 2 == 0


def test_openai_speech_logical_voice_zh(api_client: TestClient, mock_engine: MockEngine) -> None:
    response = api_client.post(
        "/v1/audio/speech",
        json={
            "model": "tts-1",
            "input": "你好",
            "voice": "zh_female",
            "response_format": "wav",
        },
    )
    assert response.status_code == 200
    assert mock_engine.calls[0]["voice"] == "zf_001"


def test_openai_speech_unknown_voice_400(api_client: TestClient) -> None:
    response = api_client.post(
        "/v1/audio/speech",
        json={
            "model": "tts-1",
            "input": "hi",
            "voice": "not_a_real_voice",
        },
    )
    assert response.status_code == 400
    assert "Unknown voice" in response.json()["detail"]


def test_openai_speech_unsupported_format_422(api_client: TestClient) -> None:
    response = api_client.post(
        "/v1/audio/speech",
        json={
            "model": "tts-1",
            "input": "hi",
            "voice": "alloy",
            "response_format": "opus",
        },
    )
    assert response.status_code == 422


def test_openai_speech_cache_header(api_client: TestClient) -> None:
    response = api_client.post(
        "/v1/audio/speech",
        json={
            "model": "tts-1",
            "input": "cache me",
            "voice": "shimmer",
            "response_format": "wav",
        },
    )
    assert response.status_code == 200
    assert response.headers[HEADER_CACHE] in {"hit", "miss", "disabled"}
