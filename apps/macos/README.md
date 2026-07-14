# Joi for macOS

Joi for macOS is a separate floating companion app. Click the avatar to reveal six controls arranged around her:

- 12 o'clock: OpenAI Realtime voice assistant.
- Top right: quick Google search in the default browser.
- Bottom right: Pomodoro timer.
- 6 o'clock: Settings.
- Bottom left: open or switch to Codex.
- Top left: Apple Music or Spotify controls for previous, play/pause, next, favorite, shuffle, and lyrics.

Drag the avatar to move Joi. The companion stays above other windows by default and has a small menu-bar item for Show, Settings, and Quit.

## Install from the DMG

1. Open `Joi-0.3.0-macOS-Universal.dmg`.
2. Drag **Joi** to **Applications**.
3. The build is ad-hoc signed rather than Apple-notarized. On first launch, Control-click Joi in Applications, choose **Open**, then confirm **Open**.
4. Click Joi, choose **Settings**, and save your own OpenAI API key. The key is stored in macOS Keychain and is never bundled with the app.
5. Start Voice and allow microphone access. Music buttons may separately request Automation permission for Music or Spotify.

The universal DMG supports Apple Silicon and Intel Macs and requires macOS 14 or later.

## Build from source

Requirements: macOS 14+, Swift 5.10+, Python 3 with Pillow, and the macOS command-line tools.

```bash
./scripts/build-macos.sh
```

The app and DMG are written to `dist/`. Run the deterministic native checks directly with:

```bash
swift build --package-path apps/macos
apps/macos/.build/arm64-apple-macosx/debug/Joi --self-test
```

## Voice privacy and cost

Voice uses `gpt-realtime-2.1` with `shimmer` by default. Realtime audio is sent to the OpenAI API while a voice session is active and may incur API charges. Stop Voice to close the session. The persona prompt identifies Joi as an AI and forbids impersonating a real partner.
