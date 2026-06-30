# Changelog

All notable changes to Sonus Companion are documented here.

## [Unreleased]

## [0.4.3] - 2026-06-30

### Fixed

- **Port race crash on engine switch (exit code 1)**: `BackendManager` now waits for the old backend process to fully exit (SIGTERM → waitUntilExit → SIGKILL escalation) and probes port 8000 is free before spawning a new uvicorn. Eliminates `[Errno 48] address already in use` → "Backend exited unexpectedly" right after switching to Qwen3.
- **Qwen MPS synthesis-time crashes**: `generate_custom_voice` failures on MPS now trigger an automatic CPU reload + single retry (previously only `from_pretrained` failures fell back to CPU).
- **Incomplete Qwen unload**: model is moved to CPU and `torch.mps.synchronize()` + `empty_cache()` run before dropping the reference, so MPS memory is actually reclaimed during hot-switch.

### Added

- `SONUS_QWEN_DEVICE` environment variable (`cpu` / `mps` / `cuda` / `auto`) to force the Qwen3-TTS device and bypass unstable MPS drivers.

## [0.4.2] - 2026-06-30

### Fixed

- **Qwen engine switch stability**: embedded Companion restarts the backend on engine change instead of hot-switching in-process (avoids Kokoro + PyTorch/MPS crashes)
- **Startup fallback**: if Qwen3 components are missing but Qwen was previously selected, fall back to Kokoro on launch
- **Memory cleanup**: Qwen/Kokoro `unload()` + `gc.collect()`; MPS load failure falls back to CPU

### Added

- `scripts/simulate-qwen-engine-switch.sh` for local engine-switch regression
- `tests/test_qwen_engine_stability.py`

## [0.4.1] - 2026-06-30

### Added

- **Lite Release**: `Sonus-macos.zip` bundles Kokoro runtime only (~120 MB)
- **Qwen on-demand**: `Sonus-qwen-addon.zip` (~224 MB) downloaded from GitHub Releases when switching to Qwen3-TTS or via Settings → **Download Qwen3 Components…**
- Qwen model snapshot (~1.7 GB) downloaded automatically with the addon flow

### Changed

- Embedded runtime no longer includes PyTorch / `qwen-tts` by default; addon installs to `~/Library/Application Support/Sonus/qwen-addon/` and is injected via `PYTHONPATH`

## [0.4.0] - 2026-06-30

### Added

- **Multi-engine TTS**: runtime hot-switch between **Kokoro** and **Qwen3-TTS** (0.6B CustomVoice) via `GET /engines` and `PUT /engines/active`
- Settings → **Engine** picker; cold start uses `SONUS_ENGINE` from UserDefaults / spawn env
- `scripts/download-qwen3-model.sh` for Qwen3 Hugging Face snapshot (~1.7GB)
- Embedded runtime bundles optional `qwen-tts` dependencies (`uv sync --extra qwen`) — **superseded in next release by Lite + on-demand addon**

### Changed

- `GET /health` includes active `engine`
- OpenAI `/v1/audio/speech` `model` must match the active engine
- Stable logical voices (`zh_female`, etc.) map per engine

## [0.3.4] - 2026-06-28

### Fixed

- **Embedded backend never starts (`Backend exited unexpectedly (code 1)`)**: `resolvePythonExecutable` returned the symlink target `python/bin/python3.12` instead of the venv shim `bin/python3.12`, so Python ran with the bundled prefix and could not activate the venv — `site-packages` resolved to `python/lib/python3.12/site-packages` (only pip) and `import sonus` failed. Now returns the shim so Python reads `pyvenv.cfg` and `site-packages` lands on `lib/python3.12/site-packages` where `sonus` is installed.
- **Backend diagnostics**: `BackendManager` now streams subprocess stdout/stderr into the app log in real time and includes the captured output in the failure message when uvicorn exits before the health-check timeout (previously stderr was discarded on fast exits).
- **Environment hygiene**: drop `PYTHONPATH`/`PYTHONHOME`/`PYTHONDONTWRITEBYTECODE` from the spawned Python process so host-side overrides cannot steer the embedded venv.

## [0.3.3] - 2026-06-28

### Fixed

- **Embedded runtime**: bundle `sonus` as a real wheel (`uv sync --no-editable`), not an editable `.pth` pointing at the CI workspace — fixes `ModuleNotFoundError: No module named 'sonus'` and backend never starting after v0.3.2
- **Release verification**: `scripts/verify-embedded-runtime.sh` checks imports, framework linkage, and `GET /health` with `models_ready=true`; CI and `build_app.sh release` run it before publishing

## [0.3.2] - 2026-06-28

### Fixed

- **Embedded runtime**: force uv-managed standalone CPython (`--managed-python`); reject python.org framework builds that crash with dyld exit code 6
- **Backend errors**: smoke-test embedded Python before spawn; surface stderr when uvicorn fails to become ready
- **App update download**: show byte-level progress (percentage and MB) with a progress panel and Settings progress bar

## [0.3.1] - 2026-06-28

### Fixed

- **Embedded runtime**: bundle uv-managed CPython prefix into the app; fix broken `python3` symlinks that pointed at CI/build-machine paths
- **Model download**: show byte-level progress (MB downloaded) instead of staying at 0% for large files
- Clearer backend error when embedded runtime is missing or broken

## [0.3.0] - 2026-06-28

### Added

- **Embedded Backend**: Release App bundles Python runtime and spawns local uvicorn (no separate `sonus serve` / Docker required)
- `BackendManager`, `ModelManager`, `EmbeddedBackendConfig`
- Settings → **Backend** status + port; **Advanced** → external server / custom models path
- First-launch model download to `~/Library/Application Support/Sonus/models/`
- `scripts/bundle-python-runtime.sh`; `build_app.sh release` embeds venv into `.app`

### Changed

- `GET /health` includes `models_ready` (Python backend)
- Debug builds default to external server; Release defaults to embedded backend

## [0.2.2] - 2026-06-28

### Added

- **App icon**: `Assets.xcassets` / `AppIcon` for Dock, Finder, and `/Applications`
- Icon source assets and generator under `SonusCompanion/scripts/`

## [0.2.1] - 2026-06-28

### Added

- **In-app updates**: GitHub Releases check, semi-automatic download/install from `/Applications/Sonus.app`
- Updater modules: `UpdateConfig`, `AppVersion`, `GitHubReleaseClient`, `UpdateDownloader`, `UpdateInstaller`, `AppUpdateController`
- Settings → **Updates**: auto-check toggle, Check Now, Install Update
- `AppVersionTests` for semver comparison

### Changed

- Menu bar label **Sonus** (was Sonus Companion)

## [0.2.0] - 2026-06-28

### Added

- **Release packaging**: `build_app.sh release` → `Sonus-macos.zip`; GitHub Actions on tag `v*`
- App rename: **`Sonus.app`**, Bundle ID **`com.sonus.app`**

### Fixed

- **Settings 窗口置前**：菜单栏点击 Settings 时激活应用并将设置窗口带到最前；设置 `moveToActiveSpace`

### Added

- **Launch at Login** via `SMAppService.mainApp` (Settings toggle)
- **Text Rules**: Paper / General Profile；Settings 管理 + Preview；Import/Export JSON
- Unit tests: `SonusCompanionTests`

### Removed

- System Voice stub — out of product scope

## [0.2.0-streaming] - 2026-06-27

### Added

- **Streaming playback** via `POST /tts/stream` (16-bit PCM @ 24 kHz)
- `StreamingAudioPlayer` using `AVAudioEngine` + `AVAudioPlayerNode` — audio starts on first chunk (lower TTFB)
- After stream completes, PCM is wrapped as WAV and saved to local cache (when cache enabled)
- Cache hit still uses instant file playback (`AVAudioPlayer`)
- Pause / resume / stop / speed change work during stream playback
- Logs: `stream ttfb_ms`, `stream complete latency_ms`

## [0.1.0] - 2026-06-27

### Added

- macOS 14+ menu bar app (`LSUIElement`, no Dock icon)
- **Speak Selection** via menu or global hotkey (default **⌥Esc**, Carbon `RegisterEventHotKey`)
- Selected text capture:
  - Level 1: Accessibility `kAXSelectedTextAttribute`
  - Level 2: clipboard fallback (simulate Cmd+C, restore pasteboard)
- Sonus HTTP client aligned with existing backend:
  - `GET /health`
  - `GET /voices` (maps `logical` voices to UI list)
  - `POST /tts` → WAV playback
- `AVAudioPlayer` with play / pause / resume / stop
- Local audio cache at `~/Library/Caches/SonusCompanion/audio/` (SHA256 key)
- Settings: server URL (default `http://127.0.0.1:8000`), voice, speed, hotkey, cache, accessibility
- File logging at `~/Library/Logs/SonusCompanion/sonus-companion.log`
- User notifications for errors

### Notes

- App Sandbox disabled (Accessibility + synthetic key events)
- Launch at Login: UI placeholder only
