#!/usr/bin/env bash
# Build a self-contained Python runtime for embedding in Sonus.app (Release).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT/SonusCompanion/build/sonus-runtime}"

echo "Building embedded Python runtime -> $OUTPUT"
rm -rf "$OUTPUT"

cd "$ROOT"

# Always use uv-managed CPython so we can copy the full prefix into the bundle.
uv python install 3.12
PYTHON_BIN="$(uv python find 3.12 --no-project --resolve-links)"
PYTHON_PREFIX="$(cd "$(dirname "$PYTHON_BIN")/.." && pwd)"

echo "Python binary: $PYTHON_BIN"
echo "Python prefix: $PYTHON_PREFIX"

uv sync --python "$PYTHON_BIN" --frozen 2>/dev/null || uv sync --python "$PYTHON_BIN"

if [[ ! -d "$ROOT/.venv" ]]; then
    echo "error: .venv not found after uv sync" >&2
    exit 1
fi

cp -R "$ROOT/.venv" "$OUTPUT"
cp -R "$PYTHON_PREFIX" "$OUTPUT/python"

# Rewire venv python shims to the bundled prefix (relative symlinks).
rm -f "$OUTPUT/bin/python" "$OUTPUT/bin/python3" "$OUTPUT/bin/python3.12"
ln -s ../python/bin/python3.12 "$OUTPUT/bin/python3.12"
ln -s python3.12 "$OUTPUT/bin/python3"
ln -s python3.12 "$OUTPUT/bin/python"

RESOLVED="$(python3 -c "import os; print(os.path.realpath('${OUTPUT}/bin/python3'))")"
EXPECTED="$(python3 -c "import os; print(os.path.realpath('${OUTPUT}/python/bin/python3.12'))")"
if [[ "$RESOLVED" != "$EXPECTED" ]]; then
    echo "error: bundled python resolves unexpectedly: $RESOLVED (expected $EXPECTED)" >&2
    exit 1
fi

# Trim dev artifacts to shrink bundle size.
find "$OUTPUT" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
find "$OUTPUT" -type d -name "tests" -prune -exec rm -rf {} + 2>/dev/null || true
find "$OUTPUT" -type d -name "test" -prune -exec rm -rf {} + 2>/dev/null || true

echo "Runtime ready: $OUTPUT/bin/python3"
"$OUTPUT/bin/python3" -c "import sonus, uvicorn, kokoro_onnx; print('imports ok')"

# Verify the bundle works when the original build-machine Python path is gone.
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin" "$SANDBOX/python"
cp -R "$OUTPUT/python/." "$SANDBOX/python/"
cp -R "$OUTPUT/lib" "$SANDBOX/lib"
cp "$OUTPUT/pyvenv.cfg" "$SANDBOX/" 2>/dev/null || true
ln -s ../python/bin/python3.12 "$SANDBOX/bin/python3.12"
ln -s python3.12 "$SANDBOX/bin/python3"
"$SANDBOX/bin/python3" -c "import sys; print(sys.executable); import sonus; print('sandbox ok')"
