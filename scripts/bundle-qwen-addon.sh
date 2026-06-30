#!/usr/bin/env bash
# Build Sonus-qwen-addon.zip — incremental PyTorch/qwen-tts packages for on-demand install.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT/SonusCompanion/build/Sonus-qwen-addon.zip}"
STAGING="${BUNDLE_QWEN_STAGING:-$ROOT/SonusCompanion/build/qwen-addon-staging}"
BASE_VENV="${BUNDLE_QWEN_BASE_VENV:-$ROOT/SonusCompanion/build/.qwen-diff-base-venv}"
QWEN_VENV="${BUNDLE_QWEN_QWEN_VENV:-$ROOT/SonusCompanion/build/.qwen-diff-qwen-venv}"

resolve_version() {
    if git -C "$ROOT" describe --tags --abbrev=0 >/dev/null 2>&1; then
        git -C "$ROOT" describe --tags --abbrev=0 | sed 's/^v//'
        return
    fi
    echo "0.0.0"
}

echo "Building Qwen addon -> $OUTPUT"
rm -rf "$STAGING" "$BASE_VENV" "$QWEN_VENV"
mkdir -p "$STAGING/site-packages"

cd "$ROOT"
export UV_MANAGED_PYTHON=1
uv python install 3.12
PYTHON_BIN="$(uv python find 3.12 --no-project --managed-python --resolve-links)"

echo "Base venv (Kokoro runtime deps)..."
uv venv "$BASE_VENV" --python "$PYTHON_BIN"
UV_PROJECT_ENVIRONMENT="$BASE_VENV" uv sync --no-editable --frozen 2>/dev/null \
    || UV_PROJECT_ENVIRONMENT="$BASE_VENV" uv sync --no-editable

echo "Qwen venv (base + --extra qwen)..."
uv venv "$QWEN_VENV" --python "$PYTHON_BIN"
UV_PROJECT_ENVIRONMENT="$QWEN_VENV" uv sync --no-editable --frozen --extra qwen 2>/dev/null \
    || UV_PROJECT_ENVIRONMENT="$QWEN_VENV" uv sync --no-editable --extra qwen

BASE_SP="$BASE_VENV/lib/python3.12/site-packages"
QWEN_SP="$QWEN_VENV/lib/python3.12/site-packages"
if [[ ! -d "$BASE_SP" || ! -d "$QWEN_SP" ]]; then
    echo "error: expected site-packages under bundle venvs" >&2
    exit 1
fi

added=0
for item in "$QWEN_SP"/*; do
    name="$(basename "$item")"
    if [[ ! -e "$BASE_SP/$name" ]]; then
        cp -R "$item" "$STAGING/site-packages/$name"
        added=$((added + 1))
    fi
done

if [[ "$added" -eq 0 ]]; then
    echo "error: no incremental packages found for qwen addon" >&2
    exit 1
fi

VERSION="$(resolve_version)"
/usr/bin/python3 - <<PY >"$STAGING/manifest.json"
import json
print(json.dumps({
    "kind": "qwen-addon",
    "version": "${VERSION}",
    "python": "3.12",
    "package_count": ${added},
}, indent=2))
PY

find "$STAGING" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
find "$STAGING" -type d -name "tests" -prune -exec rm -rf {} + 2>/dev/null || true
find "$STAGING" -type d -name "test" -prune -exec rm -rf {} + 2>/dev/null || true

rm -rf "$BASE_VENV" "$QWEN_VENV"
mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
(
    cd "$STAGING"
    COPYFILE_DISABLE=1 zip -r -X "$OUTPUT" manifest.json site-packages >/dev/null
)

echo "Qwen addon ready: $OUTPUT ($(du -sh "$OUTPUT" | awk '{print $1}'))"
echo "Packages added: $added"
