# Changelog

All notable changes to Sonus Companion are documented here.

## [Unreleased]

## [0.3.2] - 2026-06-28

### Fixed

- **Embedded runtime**: force uv-managed standalone CPython (`--managed-python`); reject python.org framework builds that crash with dyld exit code 6 on machines without `/Library/Frameworks/Python.framework`
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
