#!/usr/bin/env python3
"""Generate Sonus AppIcon.appiconset from 1024px master PNG."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ICONSET_DIR = SCRIPT_DIR.parent / "SonusCompanion/Assets.xcassets/AppIcon.appiconset"
MASTER_PATH = SCRIPT_DIR / "sonus-app-icon-1024.png"

# macOS AppIcon sizes (points, scale)
MACOS_ICON_SIZES = [
    (16, 1),
    (16, 2),
    (32, 1),
    (32, 2),
    (128, 1),
    (128, 2),
    (256, 1),
    (256, 2),
    (512, 1),
    (512, 2),
]


def render_png(size: int, dest: Path, master: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["sips", "-z", str(size), str(size), str(master), "--out", str(dest)],
        check=True,
        capture_output=True,
    )


def write_contents_json(iconset: Path) -> None:
    images = []
    for size, scale in MACOS_ICON_SIZES:
        px = size * scale
        suffix = "" if scale == 1 else f"@{scale}x"
        filename = f"icon_{size}x{size}{suffix}.png"
        images.append(
            {
                "filename": filename,
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{size}x{size}",
            }
        )

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (iconset / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n", encoding="utf-8"
    )


def main() -> int:
    if not MASTER_PATH.is_file():
        print(f"error: missing master icon at {MASTER_PATH}", file=sys.stderr)
        return 1

    iconset = ICONSET_DIR
    iconset.mkdir(parents=True, exist_ok=True)

    for size, scale in MACOS_ICON_SIZES:
        px = size * scale
        suffix = "" if scale == 1 else f"@{scale}x"
        filename = f"icon_{size}x{size}{suffix}.png"
        print(f"Rendering {filename} ({px}px)...")
        render_png(px, iconset / filename, MASTER_PATH)

    write_contents_json(iconset)
    print(f"OK: {iconset}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
