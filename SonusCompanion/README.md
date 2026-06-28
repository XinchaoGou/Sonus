# Sonus (macOS)

macOS menu bar app that reads selected text from any app and plays it via the local [Sonus](../README.md) TTS service.

## Requirements

- macOS **14.0+**
- Xcode **15+** (tested with Xcode 26)
- **Release app**: no separate server needed (embedded Python runtime + optional first-launch model download)
- **Debug / development**: Sonus server running locally (`uv run sonus serve`, default port **8000**) — Settings → Advanced → **Use external Sonus server** (Debug default)

## Build & Run

### Debug (developer — external server)

```bash
# Terminal 1 — start TTS backend
cd /path/to/Sonus
uv run sonus serve

# Terminal 2 — build app
cd /path/to/Sonus/SonusCompanion
xcodebuild -scheme SonusCompanion -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/SonusCompanion-*/Build/Products/Debug/Sonus.app
```

Or open `SonusCompanion.xcodeproj` in Xcode and press **Run**.

### Release (embedded backend)

```bash
cd /path/to/Sonus/SonusCompanion
chmod +x build_app.sh
./build_app.sh release
open build/DerivedData/Build/Products/Release/Sonus.app
```

Release bundles `Contents/Resources/sonus-runtime/` (Python venv). Models are downloaded on first launch to `~/Library/Application Support/Sonus/models/` unless already present.

## Release Build (local)

Produces `build/Sonus-macos.zip` with `Sonus.app` at the zip root (for GitHub Releases):

```bash
cd /path/to/Sonus/SonusCompanion
chmod +x build_app.sh
./build_app.sh release 0.2.0
unzip -l build/Sonus-macos.zip
```

For daily use and auto-updates, install to **`/Applications/Sonus.app`**.

Settings → **Updates** checks [GitHub Releases](https://github.com/XinchaoGou/Sonus/releases) for `Sonus-macos.zip`.

## GitHub Release

Push a version tag to build and publish `Sonus-macos.zip` via GitHub Actions:

```bash
git tag v0.2.0
git push origin v0.2.0
```

CI workflow: [`.github/workflows/companion-release.yml`](../.github/workflows/companion-release.yml).

## First Launch

1. Grant **Accessibility** access when prompted  
   System Settings → Privacy & Security → Accessibility → enable **Sonus**
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
| Launch at Login | Off (enable in Settings → System) |
| Text rules | On · Paper Reading (Settings → Manage Text Rules) |

## Logs & Cache

- Log: `~/Library/Logs/Sonus/sonus.log`
- Audio cache: `~/Library/Caches/Sonus/audio/`
- Text rules: `~/Library/Application Support/Sonus/text-rules.json`

## API Contract

Companion calls the existing Sonus endpoints:

- `GET /health`
- `GET /voices`
- `POST /tts/stream` — **primary path** (chunked PCM, play while receiving)
- Local WAV cache on stream complete; cache hit skips network

## Build & Test

```bash
cd SonusCompanion
xcodebuild -scheme SonusCompanion -destination 'platform=macOS' build test
```

See [docs/COMPANION.md](../docs/COMPANION.md) for architecture details.  
Text rules: [docs/TEXT_RULES.md](../docs/TEXT_RULES.md).
