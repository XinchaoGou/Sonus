"""Split long plain text into synthesis-friendly chunks."""

from __future__ import annotations

import re

# Prefer breaking after these (searched from the end of the window).
_BREAK_PRIORITY: tuple[re.Pattern[str], ...] = (
    re.compile(r"\n{2,}"),
    re.compile(r"\n"),
    re.compile(r'[.!?。！？…]+["\'」』\)\]]*'),
    re.compile(r"[,，;；:：]+"),
    re.compile(r"\s+"),
)


def split_text(text: str, max_chars: int) -> list[str]:
    """Return non-empty chunks each at most *max_chars* (when splitting is enabled).

    When *max_chars* is ``<= 0`` or the text fits, returns a single-element list.
    """
    stripped = text.strip()
    if not stripped:
        return []
    if max_chars <= 0 or len(stripped) <= max_chars:
        return [stripped]

    chunks: list[str] = []
    remaining = stripped
    while remaining:
        if len(remaining) <= max_chars:
            chunks.append(remaining.strip())
            break

        window = remaining[:max_chars]
        split_at = _find_break_index(window, max_chars)
        piece = remaining[:split_at].strip()
        if piece:
            chunks.append(piece)
        remaining = remaining[split_at:].lstrip()

    return [c for c in chunks if c]


def _find_break_index(window: str, max_chars: int) -> int:
    """Index in *window* to split before; ``max_chars`` means hard break."""
    best = -1
    for pattern in _BREAK_PRIORITY:
        for match in pattern.finditer(window):
            end = match.end()
            if 0 < end < max_chars:
                best = max(best, end)
        if best > 0:
            return best
    return max_chars
