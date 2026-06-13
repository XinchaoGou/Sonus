#!/usr/bin/env bash
# Download Kokoro model files into ./models (for local uv or Docker volume mount).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS="${ROOT}/models"

mkdir -p "${MODELS}"

download() {
  local url="$1"
  local dest="$2"
  if [[ -f "${dest}" ]]; then
    echo "skip (exists): ${dest}"
    return 0
  fi
  echo "download: ${dest}"
  curl -fsSL -o "${dest}" "${url}"
}

download \
  "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx" \
  "${MODELS}/kokoro-v1.0.onnx"

download \
  "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin" \
  "${MODELS}/voices-v1.0.bin"

download \
  "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.1-zh.onnx" \
  "${MODELS}/kokoro-v1.1-zh.onnx"

download \
  "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.1-zh.bin" \
  "${MODELS}/voices-v1.1-zh.bin"

download \
  "https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh/raw/main/config.json" \
  "${MODELS}/kokoro-v1.1-zh-config.json"

echo "done. models in ${MODELS}"
ls -lh "${MODELS}"
