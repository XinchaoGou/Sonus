#!/usr/bin/env bash
# Build a self-contained Python runtime for embedding in Sonus.app (Release).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT/SonusCompanion/build/sonus-runtime}"
BUNDLE_VENV="${BUNDLE_VENV:-$ROOT/SonusCompanion/build/.bundle-venv}"

echo "Building embedded Python runtime -> $OUTPUT"
rm -rf "$OUTPUT" "$BUNDLE_VENV"

cd "$ROOT"

export UV_MANAGED_PYTHON=1

# Always use uv-managed standalone CPython (never python.org framework builds).
uv python install 3.12
PYTHON_BIN="$(uv python find 3.12 --no-project --managed-python --resolve-links)"
PYTHON_PREFIX="$(cd "$(dirname "$PYTHON_BIN")/.." && pwd)"

echo "Python binary: $PYTHON_BIN"
echo "Python prefix: $PYTHON_PREFIX"

if otool -L "$PYTHON_BIN" | grep -q '/Library/Frameworks/Python.framework/'; then
    echo "error: $PYTHON_BIN links to python.org framework; expected uv-managed standalone build" >&2
    echo "hint: run 'uv python install --reinstall 3.12' and retry with --managed-python" >&2
    exit 1
fi

# Install into an isolated venv with sonus as a real package (not editable .pth).
uv venv "$BUNDLE_VENV" --python "$PYTHON_BIN"
export UV_PROJECT_ENVIRONMENT="$BUNDLE_VENV"
uv sync --no-editable --frozen 2>/dev/null || uv sync --no-editable

if [[ ! -d "$BUNDLE_VENV/lib/python3.12/site-packages/sonus" ]]; then
    echo "error: sonus package missing from bundle venv site-packages" >&2
    exit 1
fi
if [[ -f "$BUNDLE_VENV/lib/python3.12/site-packages/sonus.pth" ]]; then
    echo "error: editable sonus.pth must not be present in release bundle" >&2
    exit 1
fi

cp -R "$BUNDLE_VENV/." "$OUTPUT"
cp -R "$PYTHON_PREFIX" "$OUTPUT/python"

# Rewire venv python shims to the bundled prefix (relative symlinks).
rm -f "$OUTPUT/bin/python" "$OUTPUT/bin/python3" "$OUTPUT/bin/python3.12"
ln -s ../python/bin/python3.12 "$OUTPUT/bin/python3.12"
ln -s python3.12 "$OUTPUT/bin/python3"
ln -s python3.12 "$OUTPUT/bin/python"

RESOLVED="$(/usr/bin/python3 -c "import os; print(os.path.realpath('${OUTPUT}/bin/python3'))")"
EXPECTED="$(/usr/bin/python3 -c "import os; print(os.path.realpath('${OUTPUT}/python/bin/python3.12'))")"
if [[ "$RESOLVED" != "$EXPECTED" ]]; then
    echo "error: bundled python resolves unexpectedly: $RESOLVED (expected $EXPECTED)" >&2
    exit 1
fi

# Trim dev artifacts to shrink bundle size.
find "$OUTPUT" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
find "$OUTPUT" -type d -name "tests" -prune -exec rm -rf {} + 2>/dev/null || true
find "$OUTPUT" -type d -name "test" -prune -exec rm -rf {} + 2>/dev/null || true

echo "Runtime ready: $OUTPUT/bin/python3"
SONUS_FILE="$("$OUTPUT/bin/python3" -c "import sonus; print(sonus.__file__)")"
SONUS_REAL="$(/usr/bin/python3 -c "import os; print(os.path.realpath('${SONUS_FILE}'))")"
OUTPUT_REAL="$(/usr/bin/python3 -c "import os; print(os.path.realpath('${OUTPUT}'))")"
case "$SONUS_REAL" in
    "$OUTPUT_REAL"*) ;;
    *)
        echo "error: sonus resolves outside bundle: $SONUS_REAL (bundle=$OUTPUT_REAL)" >&2
        exit 1
        ;;
esac
"$OUTPUT/bin/python3" -c "import sonus, uvicorn, kokoro_onnx; print('imports ok')"

# Verify the bundle works when copied to a fresh directory.
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
cp -R "$OUTPUT/." "$SANDBOX/"
"$SANDBOX/bin/python3" -c "import sys; print(sys.executable); import sonus; print('sandbox ok', sonus.__file__)"

if otool -L "$OUTPUT/python/bin/python3.12" | grep -q '/Library/Frameworks/Python.framework/'; then
    echo "error: bundled python3.12 still references /Library/Frameworks/Python.framework" >&2
    exit 1
fi

rm -rf "$BUNDLE_VENV"
