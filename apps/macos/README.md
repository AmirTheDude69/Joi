# Joi for macOS

Joi for macOS is a separate floating companion app. Click the avatar to reveal six controls in a circular AssistiveTouch-style layout:

- 12 o'clock: OpenAI Realtime voice assistant.
- Top right: quick Google search in the default browser.
- Bottom right: compact Focus timer.
- 6 o'clock: Settings.
- Bottom left: open or switch to Codex.
- Top left: a watchOS-style Apple Music or Spotify honeycomb for previous, play/pause, next, favorite, shuffle, and lyrics. Favorite works through Apple Music; Spotify's current Mac automation API exposes its saved state as read-only, so Joi shows an honest prompt to use Spotify's + button instead.

The primary actions are frameless SF Symbols with invisible accessible hit targets. Search, Focus, and Voice keep their selected control visible; click that same control again to close or stop it. Drag the avatar to move Joi. The companion stays above other windows by default and has a small menu-bar item for Show, Settings, and Quit.

## Install from the DMG

1. Open `Joi-0.4.0-macOS-Universal.dmg`.
2. Drag **Joi** to **Applications**.
3. This private-beta build is ad-hoc signed rather than Apple-notarized. On first launch, Control-click Joi in Applications, choose **Open**, then confirm **Open**.
4. Click Joi, choose **Settings**, and save your own OpenAI API key. The key is stored in macOS Keychain and is never bundled with the app.
5. Click **Voice** once and allow microphone access. Joi connects, listens, and answers continuously; interrupt naturally while she is speaking. Click **Voice** again to end the session.
6. Music controls may separately request Automation permission for Music or Spotify.

The universal DMG supports Apple Silicon and Intel Macs and requires macOS 14 or later.

## Focus timer

Click **Focus** to open the compact Clock-style card. Pick 15, 25, 30, or 45 minutes and press Start. The same Focus icon closes the card without cancelling an active timer. Reopen it to pause, resume, or reset the timer. Completion plays a sound, posts a notification when permitted, and triggers Joi's celebration animation.

## Natural avatar behavior

The app uses every standard animation row in the canonical v2 spritesheet:

- Idle gestures rotate naturally instead of repeating one loop forever.
- Opening and closing the menu use the right/left motion rows.
- Voice listening, speaking, and errors map to waiting, waving, and failed.
- Focus maps to working, then jumping and waving on completion.
- Search and Settings use review.
- Music actions and Codex launches trigger short contextual flourishes.
- While otherwise idle, Joi follows the pointer with all 16 planted-body gaze poses.

Reduce Motion in Settings disables cycling and pointer-gaze movement.

## Build from source

Requirements: macOS 14+, Swift 5.10+, Python 3 with Pillow, and the macOS command-line tools.

```bash
./scripts/build-macos.sh
```

The app and versioned DMG are written to `dist/`. Run the deterministic native checks directly with:

```bash
swift build --package-path apps/macos
swift run --skip-build --package-path apps/macos Joi --self-test
```

## Voice privacy and cost

Voice uses `gpt-realtime-2.1` with the warm `shimmer` voice by default, continuous semantic voice-activity detection, and client-side interruption handling. Realtime microphone audio is sent to the OpenAI API only while a voice session is active and may incur API charges. The persona prompt identifies Joi as an AI and forbids impersonating a real partner.

This private BYOK build stores the user's project key in Keychain. A future public distribution should use a backend and short-lived client credentials rather than shipping a provider key.
