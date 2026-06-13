"""Tests for long-text chunking."""

from sonus.text_split import split_text


def test_split_short_text_unchanged() -> None:
    assert split_text("你好世界", 280) == ["你好世界"]


def test_split_disabled_when_max_zero() -> None:
    text = "a" * 500
    assert split_text(text, 0) == [text]


def test_split_on_paragraph() -> None:
    text = "第一段内容。\n\n第二段内容。"
    chunks = split_text(text, 12)
    assert len(chunks) >= 2
    assert "".join(chunks).replace("\n", "") == text.replace("\n", "")


def test_split_on_sentence_punctuation() -> None:
    text = "这是第一句。这是第二句。这是第三句。"
    chunks = split_text(text, 15)
    assert len(chunks) >= 2
    for chunk in chunks:
        assert len(chunk) <= 15


def test_split_hard_break_when_no_delimiter() -> None:
    text = "a" * 40
    chunks = split_text(text, 15)
    assert len(chunks) == 3
    assert sum(len(c) for c in chunks) == 40


def test_split_empty_returns_empty_list() -> None:
    assert split_text("   ", 100) == []
