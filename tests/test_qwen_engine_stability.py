"""Engine switch stability tests (unload, round-trip, MPS fallback hooks)."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from sonus.config import Settings
from sonus.engine_manager import EngineManager, EngineSwitchError
from sonus.engines.qwen3_tts import Qwen3TTSEngine
from conftest import MockEngine


class TrackingMockEngine(MockEngine):
    def __init__(self, engine_id: str = "kokoro", voices: list[str] | None = None) -> None:
        super().__init__(voices=voices)
        self.engine_id = engine_id
        self.unload_count = 0

    def unload(self) -> None:
        self.unload_count += 1


@pytest.fixture
def dual_engine_settings(tmp_path: Path) -> Settings:
    for name in (
        "kokoro-v1.0.onnx",
        "voices-v1.0.bin",
        "kokoro-v1.1-zh.onnx",
        "voices-v1.1-zh.bin",
        "kokoro-v1.1-zh-config.json",
    ):
        (tmp_path / name).write_bytes(b"x")
    qwen_dir = tmp_path / "qwen3-tts"
    qwen_dir.mkdir()
    (qwen_dir / "config.json").write_text("{}")
    (qwen_dir / "model.safetensors").write_bytes(b"x")
    return Settings(models_dir=tmp_path, engine="kokoro")


def test_switch_unloads_previous_engine(
    dual_engine_settings: Settings, monkeypatch: pytest.MonkeyPatch
) -> None:
    kokoro = TrackingMockEngine(engine_id="kokoro")
    qwen = TrackingMockEngine(engine_id="qwen3-tts", voices=["serena"])

    def build(settings: Settings) -> TrackingMockEngine:
        if settings.engine == "qwen3-tts":
            return qwen
        return kokoro

    monkeypatch.setattr("sonus.engine_manager.build_engine", build)
    manager = EngineManager(dual_engine_settings)
    assert manager.active_engine_id == "kokoro"

    manager.switch_engine("qwen3-tts")
    assert kokoro.unload_count == 1
    assert manager.active_engine_id == "qwen3-tts"
    assert manager.tts.engine_id == "qwen3-tts"

    manager.switch_engine("kokoro")
    assert qwen.unload_count == 1
    assert manager.active_engine_id == "kokoro"


def test_switch_round_trip_preserves_tts_service(
    dual_engine_settings: Settings, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        "sonus.engine_manager.build_engine",
        lambda settings: TrackingMockEngine(engine_id=settings.engine),
    )
    manager = EngineManager(dual_engine_settings)

    for engine_id in ("qwen3-tts", "kokoro", "qwen3-tts", "kokoro"):
        manager.switch_engine(engine_id)
        assert manager.active_engine_id == engine_id
        assert manager.tts.engine_id == engine_id


def test_switch_rejects_qwen_without_optional_dep(
    dual_engine_settings: Settings, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("sonus.engine_manager.build_engine", lambda settings: MockEngine())

    import sonus.engine_manager as engine_manager_module

    original_check = engine_manager_module._check_optional_dependency

    def fail_qwen(spec) -> None:
        if spec.optional_dependency == "qwen":
            raise EngineSwitchError("Qwen3-TTS requires optional dependencies.")
        original_check(spec)

    monkeypatch.setattr(engine_manager_module, "_check_optional_dependency", fail_qwen)
    manager = EngineManager(dual_engine_settings)

    with pytest.raises(EngineSwitchError, match="optional dependencies"):
        manager.switch_engine("qwen3-tts")


def test_qwen_unload_clears_model_and_runs_gc(tmp_path: Path) -> None:
    engine = Qwen3TTSEngine(tmp_path)
    sentinel = object()
    engine._model = sentinel  # type: ignore[assignment]

    with patch("sonus.engines.qwen3_tts.gc.collect") as collect_mock:
        engine.unload()

    assert engine._model is None
    collect_mock.assert_called_once()


def test_qwen_mps_load_falls_back_to_cpu(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    import sys

    qwen_dir = tmp_path / "qwen3-tts"
    qwen_dir.mkdir()
    (qwen_dir / "config.json").write_text("{}")
    engine = Qwen3TTSEngine(qwen_dir)

    fake_model = MagicMock()
    device_maps: list[str] = []

    def from_pretrained(*_args, **kwargs):
        device_maps.append(kwargs["device_map"])
        if kwargs["device_map"] == "mps":
            raise RuntimeError("mps oom")
        return fake_model

    fake_torch = MagicMock()
    fake_torch.backends.mps.is_available.return_value = True
    fake_torch.cuda.is_available.return_value = False
    fake_torch.float32 = float

    fake_qwen_module = MagicMock()
    fake_qwen_module.Qwen3TTSModel.from_pretrained.side_effect = from_pretrained

    monkeypatch.setitem(sys.modules, "torch", fake_torch)
    monkeypatch.setitem(sys.modules, "qwen_tts", fake_qwen_module)

    loaded = engine._ensure_loaded()

    assert loaded is fake_model
    assert device_maps == ["mps", "cpu"]
