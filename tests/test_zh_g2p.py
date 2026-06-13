"""Tests for Chinese G2P helpers (zh/en mixed text)."""

from unittest.mock import MagicMock, patch

from sonus.zh_g2p import build_en_callable, build_zh_g2p, phonemes_from_g2p_result


def test_phonemes_from_g2p_result_string() -> None:
    assert phonemes_from_g2p_result("həˈloʊ") == "həˈloʊ"


def test_phonemes_from_g2p_result_tuple() -> None:
    assert phonemes_from_g2p_result(("həˈloʊ", [])) == "həˈloʊ"


def test_phonemes_from_g2p_result_empty_tuple() -> None:
    assert phonemes_from_g2p_result(()) == ""


@patch("sonus.zh_g2p.build_en_callable")
def test_build_zh_g2p_en_mixed_enabled(mock_build_en: MagicMock) -> None:
    mock_en = MagicMock(return_value="hello")
    mock_build_en.return_value = mock_en
    fake_zh = MagicMock()
    with patch("misaki.zh.ZHG2P", fake_zh) as mock_zh_g2p:
        g2p = build_zh_g2p(en_mixed=True)
    mock_build_en.assert_called_once_with(british=False)
    mock_zh_g2p.assert_called_once_with(version="1.1", en_callable=mock_en)
    assert g2p is fake_zh.return_value


@patch("sonus.zh_g2p.build_en_callable")
def test_build_zh_g2p_en_mixed_disabled(mock_build_en: MagicMock) -> None:
    fake_zh = MagicMock()
    with patch("misaki.zh.ZHG2P", fake_zh) as mock_zh_g2p:
        g2p = build_zh_g2p(en_mixed=False)
    mock_build_en.assert_not_called()
    mock_zh_g2p.assert_called_once_with(version="1.1", en_callable=None)
    assert g2p is fake_zh.return_value


def test_build_en_callable_unwraps_tuple() -> None:
    mock_espeak_g2p = MagicMock(return_value=("sˈOnəs", None))
    with patch("misaki.espeak.EspeakG2P", return_value=mock_espeak_g2p):
        en_callable = build_en_callable()
    assert en_callable("Sonus") == "sˈOnəs"
    mock_espeak_g2p.assert_called_once_with("Sonus")


def test_zh_g2p_mixed_text_includes_english_phonemes() -> None:
    g2p = build_zh_g2p(en_mixed=True)
    phonemes, _ = g2p("你好 Sonus")
    assert "s" in phonemes.lower() or "On" in phonemes
