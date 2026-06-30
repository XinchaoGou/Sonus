#!/usr/bin/env bash
# Download Qwen3-TTS 0.6B CustomVoice snapshot for Sonus qwen3-tts engine.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS_DIR="${SONUS_MODELS_DIR:-$ROOT/models}"
TARGET="${MODELS_DIR}/qwen3-tts"
REPO="Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"

cd "$ROOT"

if [[ -f "${TARGET}/config.json" ]]; then
  echo "Qwen3-TTS already present at ${TARGET}"
  exit 0
fi

echo "Downloading ${REPO} into ${TARGET} ..."
mkdir -p "${TARGET}"

TARGET="${TARGET}" REPO="${REPO}" uv run --extra qwen python - <<'PY'
import os
import sys

target = os.environ.get("TARGET")
repo = os.environ.get("REPO")
if not target or not repo:
    raise SystemExit("TARGET/REPO not set")

try:
    from huggingface_hub import snapshot_download
except ImportError:
    print("Installing huggingface_hub ...", file=sys.stderr)
    import subprocess

    subprocess.check_call([sys.executable, "-m", "pip", "install", "huggingface_hub"])
    from huggingface_hub import snapshot_download

snapshot_download(repo_id=repo, local_dir=target)
print(f"Done: {target}")
PY

echo "Qwen3-TTS ready at ${TARGET}"
