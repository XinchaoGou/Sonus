#!/usr/bin/env bash
# Simulate Companion-style engine switching: hot-switch + process restart paths.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODELS_DIR="${SONUS_MODELS_DIR:-$HOME/Library/Application Support/Sonus/models}"
PORT="${SONUS_SIM_PORT:-8765}"
BASE="http://127.0.0.1:${PORT}"
QWEN_ADDON="${HOME}/Library/Application Support/Sonus/qwen-addon/site-packages"
LOG_DIR="$(mktemp -d /tmp/sonus-sim-XXXXXX)"
PID=""

cleanup() {
  if [[ -n "${PID}" ]] && kill -0 "${PID}" 2>/dev/null; then
    kill "${PID}" 2>/dev/null || true
    wait "${PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

require_file() {
  if [[ ! -e "$1" ]]; then
    echo "SKIP: missing $1"
    exit 0
  fi
}

require_file "${MODELS_DIR}/kokoro-v1.0.onnx"
require_file "${MODELS_DIR}/qwen3-tts/config.json"
require_file "${QWEN_ADDON}/qwen_tts/__init__.py"

wait_health() {
  local label="$1"
  local tries="${2:-60}"
  for _ in $(seq 1 "$tries"); do
    if curl -sf "${BASE}/health" >/dev/null 2>&1; then
      echo "OK: ${label} healthy"
      return 0
    fi
    sleep 0.5
  done
  echo "FAIL: ${label} not healthy"
  tail -40 "${LOG_DIR}/backend.log" || true
  return 1
}

spawn_backend() {
  local engine="$1"
  local log="${LOG_DIR}/backend-${engine}-$$.log"
  echo "--- spawn SONUS_ENGINE=${engine} ---"
  SONUS_HOST=127.0.0.1 \
  SONUS_PORT="${PORT}" \
  SONUS_MODELS_DIR="${MODELS_DIR}" \
  SONUS_ENGINE="${engine}" \
  PYTHONPATH="${QWEN_ADDON}:${PYTHONPATH:-}" \
  uv run --extra qwen uvicorn sonus.app:app --host 127.0.0.1 --port "${PORT}" \
    >"${log}" 2>&1 &
  PID=$!
  ln -sf "${log}" "${LOG_DIR}/backend.log"
  local tries=60
  if [[ "${engine}" == "qwen3-tts" ]]; then
    tries=90
  fi
  wait_health "engine=${engine}" "${tries}"
  curl -sS "${BASE}/health" | python3 -m json.tool
}

stop_backend() {
  if [[ -n "${PID}" ]] && kill -0 "${PID}" 2>/dev/null; then
    kill "${PID}" 2>/dev/null || true
    wait "${PID}" 2>/dev/null || true
    local code=$?
    echo "--- backend stopped (exit=${code}) ---"
    PID=""
    sleep 1
  fi
}

tts_smoke() {
  local label="$1"
  local voice="${2:-zh_female}"
  local out="${LOG_DIR}/${label}.wav"
  local max_time="${3:-180}"
  echo "--- TTS ${label} (voice=${voice}, timeout=${max_time}s) ---"
  local http_code
  http_code=$(curl -sS --max-time "${max_time}" -X POST "${BASE}/tts" \
    -H 'Content-Type: application/json' \
    -d "{\"text\":\"测试\",\"voice\":\"${voice}\",\"speed\":1.0,\"format\":\"wav\"}" \
    -o "${out}" -w "%{http_code}")
  if [[ "${http_code}" != "200" ]]; then
    echo "FAIL: ${label} HTTP ${http_code}"
    head -c 500 "${out}" 2>/dev/null || true
    echo
    return 1
  fi
  local size
  size=$(wc -c <"${out}" | tr -d ' ')
  if [[ "${size}" -lt 1000 ]]; then
    echo "FAIL: ${label} wav too small (${size} bytes)"
    return 1
  fi
  echo "OK: ${label} wav ${size} bytes"
}

hot_switch() {
  local target="$1"
  echo "--- hot switch -> ${target} ---"
  curl -sf -X PUT "${BASE}/engines/active" \
    -H 'Content-Type: application/json' \
    -d "{\"engine\":\"${target}\"}" | python3 -m json.tool
  curl -sS "${BASE}/health" | python3 -m json.tool
}

echo "Simulation log dir: ${LOG_DIR}"
echo "Models: ${MODELS_DIR}"

echo "== Phase 1: hot-switch path (CLI/API) =="
spawn_backend kokoro
tts_smoke kokoro zh_female 60
hot_switch qwen3-tts
tts_smoke qwen_after_hot_switch zh_female 180
hot_switch kokoro
tts_smoke kokoro_after_switch zh_female 60
stop_backend

echo "== Phase 2: restart path (Companion embedded) =="
spawn_backend qwen3-tts
tts_smoke qwen_restart zh_female 180
stop_backend
spawn_backend kokoro
tts_smoke kokoro_restart zh_female 60
stop_backend

echo "== Phase 3: rapid restart cycles (2x) =="
for i in 1 2; do
  spawn_backend qwen3-tts
  tts_smoke "qwen_cycle_${i}" zh_female 180
  stop_backend
  spawn_backend kokoro
  tts_smoke "kokoro_cycle_${i}" zh_female 60
  stop_backend
done

echo "ALL SIMULATION PHASES PASSED"
