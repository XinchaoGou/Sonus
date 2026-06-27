# Sonus Companion

macOS menu bar app that reads selected text from any app and plays it via the local [Sonus](../README.md) TTS service.

## Requirements

- macOS **14.0+**
- Xcode **15+** (tested with Xcode 26)
- Sonus server running locally (`uv run sonus serve`, default port **8000**)

## Build & Run

```bash
# Terminal 1 — start TTS backend
cd /path/to/Sonus
uv run sonus serve

# Terminal 2 — build Companion
cd /path/to/Sonus/SonusCompanion
xcodebuild -scheme SonusCompanion -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/SonusCompanion-*/Build/Products/Debug/SonusCompanion.app
```

Or open `SonusCompanion.xcodeproj` in Xcode and press **Run**.

## First Launch

1. Grant **Accessibility** access when prompted  
   System Settings → Privacy & Security → Accessibility → enable **SonusCompanion**
2. Optional: allow notifications for error toasts
3. Select text in any app → press **⌥Esc** or use menu **Speak Selection**

## Settings

| Option | Default |
|--------|---------|
| Server URL | `http://127.0.0.1:8000` |
| Voice | `zh_female` |
| Speed | 1.0× |
| Hotkey | ⌥Esc |
| Clipboard fallback | On |
| Local cache | On |

## Logs & Cache

- Log: `~/Library/Logs/SonusCompanion/sonus-companion.log`
- Audio cache: `~/Library/Caches/SonusCompanion/audio/`

## API Contract

Companion calls the existing Sonus endpoints:

- `GET /health`
- `GET /voices`
- `POST /tts/stream` — **primary path** (chunked PCM, play while receiving)
- Local WAV cache on stream complete; cache hit skips network

See [docs/COMPANION.md](../docs/COMPANION.md) for architecture details.

## Phase 2

System Voice integration is stubbed only. See [docs/SYSTEM_VOICE_RESEARCH.md](../docs/SYSTEM_VOICE_RESEARCH.md).
