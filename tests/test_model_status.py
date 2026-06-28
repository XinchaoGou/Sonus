"""Tests for model file readiness helpers."""

from pathlib import Path

from sonus.config import Settings
from sonus.model_status import missing_model_files, models_ready


def test_models_ready_when_all_files_exist(tmp_path: Path) -> None:
    for name in (
        "kokoro-v1.0.onnx",
        "voices-v1.0.bin",
        "kokoro-v1.1-zh.onnx",
        "voices-v1.1-zh.bin",
        "kokoro-v1.1-zh-config.json",
    ):
        (tmp_path / name).write_bytes(b"x")

    settings = Settings(models_dir=tmp_path)
    assert models_ready(settings) is True
    assert missing_model_files(settings) == []


def test_models_not_ready_reports_missing(tmp_path: Path) -> None:
    settings = Settings(models_dir=tmp_path)
    assert models_ready(settings) is False
    missing = missing_model_files(settings)
    assert len(missing) == 5
    assert all(str(tmp_path) in path for path in missing)
