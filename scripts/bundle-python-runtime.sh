#!/usr/bin/env bash
# Build a portable Python venv for embedding in Sonus.app (Release).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT/SonusCompanion/build/sonus-runtime}"

echo "Building embedded Python runtime -> $OUTPUT"
rm -rf "$OUTPUT"

cd "$ROOT"
uv sync --python 3.12 --frozen 2>/dev/null || uv sync --python 3.12

if [[ ! -d "$ROOT/.venv" ]]; then
    echo "error: .venv not found after uv sync" >&2
    exit 1
fi

cp -R "$ROOT/.venv" "$OUTPUT"

# Trim dev artifacts to shrink bundle size.
find "$OUTPUT" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
find "$OUTPUT" -type d -name "tests" -prune -exec rm -rf {} + 2>/dev/null || true
find "$OUTPUT" -type d -name "test" -prune -exec rm -rf {} + 2>/dev/null || true

echo "Runtime ready: $OUTPUT/bin/python3"
"$OUTPUT/bin/python3" -c "import sonus, uvicorn, kokoro_onnx; print('imports ok')"
