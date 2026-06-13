"""Tests for logging helpers."""

import uuid

import pytest

from sonus.logging_config import configure_logging, new_request_id, normalize_log_level


def test_normalize_log_level() -> None:
    assert normalize_log_level("INFO") == "info"
    assert normalize_log_level(" Debug ") == "debug"


def test_normalize_log_level_invalid() -> None:
    with pytest.raises(ValueError, match="Invalid log level"):
        normalize_log_level("verbose")


def test_new_request_id_reuses_client_value() -> None:
    assert new_request_id("  client-id-1  ") == "client-id-1"


def test_new_request_id_generates_uuid() -> None:
    rid = new_request_id(None)
    uuid.UUID(rid)


def test_configure_logging_returns_normalized_level() -> None:
    assert configure_logging("warning") == "warning"
