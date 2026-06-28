# Changelog

All notable changes to Sonus Companion are documented here.

## [Unreleased]

### Fixed

- **Settings 窗口置前**：菜单栏点击 Settings 时激活应用并将设置窗口带到最前；设置 `moveToActiveSpace`，在当前桌面显示而非跳回首次打开的 Space

### Added

- **Launch at Login** via `SMAppService.mainApp` (Settings toggle)
- Pending approval hint + shortcut to System Settings → Login Items
- **Text Rules**: TTS 前可配置正则/字面量替换；Paper / General Profile；Settings 管理 + Preview；Import/Export JSON；菜单栏 Profile 切换
- Unit tests: `SonusCompanionTests`（`TextPreprocessor` / `TextRuleStore`）

### Removed

- System Voice stub (`SonusSystemVoiceInstaller`) and Settings placeholder — out of product scope

## [0.2.0] - 2026-06-27

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
