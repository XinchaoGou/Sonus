#!/usr/bin/env bash
# End-to-end verification for an embedded sonus-runtime directory or Sonus.app bundle.
set -euo pipefail

TARGET="${1:-}"
PORT="${2:-19099}"
MODELS_DIR="${SONUS_MODELS_DIR:-$HOME/Library/Application Support/Sonus/models}"

usage() {
    cat <<EOF
Usage: $0 <sonus-runtime-dir|Sonus.app> [port]

Checks:
  - python3 resolves inside bundle
  - import sonus/uvicorn (sonus package lives inside bundle)
  - no python.org framework linkage
  - uvicorn serves GET /health with models_ready when models exist
EOF
}

if [[ -z "$TARGET" ]]; then
    usage
    exit 1
fi

require_models="${SONUS_VERIFY_MODELS:-auto}"
if [[ "$require_models" == "auto" ]]; then
    if [[ -f "$MODELS_DIR/kokoro-v1.0.onnx" && -f "$MODELS_DIR/voices-v1.0.bin" \
        && -f "$MODELS_DIR/kokoro-v1.1-zh.onnx" && -f "$MODELS_DIR/voices-v1.1-zh.bin" \
        && -f "$MODELS_DIR/kokoro-v1.1-zh-config.json" ]]; then
        require_models=1
    else
        require_models=0
    fi
fi

if [[ -d "$TARGET/Contents/Resources/sonus-runtime" ]]; then
    RUNTIME="$TARGET/Contents/Resources/sonus-runtime"
elif [[ -d "$TARGET/bin" && -d "$TARGET/python" ]]; then
    RUNTIME="$TARGET"
else
    echo "error: expected sonus-runtime directory or Sonus.app, got: $TARGET" >&2
    exit 1
fi

PYTHON="$RUNTIME/bin/python3"
if [[ ! -x "$PYTHON" && ! -L "$PYTHON" ]]; then
    echo "error: missing $PYTHON" >&2
    exit 1
fi

RESOLVED="$(/usr/bin/python3 -c "import os; print(os.path.realpath('${PYTHON}'))")"
case "$RESOLVED" in
    "$RUNTIME"*) ;;
    *)
        echo "error: python resolves outside runtime: $RESOLVED" >&2
        exit 1
        ;;
esac

if otool -L "$RUNTIME/python/bin/python3.12" | grep -q '/Library/Frameworks/Python.framework/'; then
    echo "error: python3.12 links to python.org framework" >&2
    exit 1
fi

export PATH="$RUNTIME/bin:/usr/bin:/bin"
export PYTHONUNBUFFERED=1
export SONUS_MODELS_DIR="$MODELS_DIR"
export SONUS_CACHE_DIR="${TMPDIR:-/tmp}/sonus-verify-cache"
export SONUS_LOG_LEVEL=info

SONUS_FILE="$("$PYTHON" -c "import sonus, uvicorn; print(sonus.__file__)")"
case "$SONUS_FILE" in
    "$RUNTIME"*) ;;
    *)
        echo "error: sonus resolves outside runtime: $SONUS_FILE" >&2
        exit 1
        ;;
esac

echo "OK imports: $SONUS_FILE"

"$PYTHON" -m uvicorn sonus.app:app --host 127.0.0.1 --port "$PORT" --log-level warning &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

deadline=$((SECONDS + 30))
while (( SECONDS < deadline )); do
    if curl -fsS "http://127.0.0.1:${PORT}/health" >/tmp/sonus-health.json 2>/dev/null; then
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "error: uvicorn exited before becoming ready" >&2
        exit 1
    fi
    sleep 0.4
done

if [[ ! -f /tmp/sonus-health.json ]]; then
    echo "error: /health not reachable on port $PORT within 30s" >&2
    exit 1
fi

/usr/bin/python3 -c "
import json
body = json.load(open('/tmp/sonus-health.json'))
require_models = ${require_models}
if require_models:
    assert body.get('status') == 'ok', body
    assert body.get('models_ready') is True, body
    print('OK health with models:', body)
else:
    assert body.get('status') in ('ok', 'degraded'), body
    print('OK health (models not required on this host):', body)
"

echo "verify-embedded-runtime: all checks passed"
