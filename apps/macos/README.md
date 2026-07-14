# Joi for macOS

Joi for macOS is a separate floating companion app. Click the avatar to reveal six controls in a circular AssistiveTouch-style layout:

- 12 o'clock: OpenAI Realtime voice assistant.
- Top right: quick Google search in the default browser.
- Bottom right: compact Focus timer.
- 6 o'clock: Settings.
- Bottom left: open or switch to Codex.
- Top left: a watchOS-style media honeycomb for previous, pause, next, favorite, shuffle, and lyrics. The three transport controls use standard macOS media keys only when the current Now Playing owner matches a recognized browser or media app that is actively producing audio, so they control the current source—including Spotify in Arc—without defaulting to Apple Music. Favorite, shuffle, and lyrics work only when that same current owner is a playing native Music or Spotify app; ambiguous/browser sources fail closed with a helpful message.

The primary actions are frameless SF Symbols with generous invisible hit targets, including the hollow center of Search. Search, Focus, and Voice keep their selected control visible; click that same control again to close or stop it. A voice error card can also be clicked directly to dismiss it. Drag the avatar to move Joi with screen-space tracking. The companion stays above other windows by default and has a small menu-bar item for Show, Settings, and Quit.

## Install from the DMG

1. Open `Joi-0.4.1-macOS-Universal.dmg`.
2. Drag **Joi** to **Applications**.
3. This private-beta build is ad-hoc signed rather than Apple-notarized. On first launch, Control-click Joi in Applications, choose **Open**, then confirm **Open**.
4. Click Joi, choose **Settings**, and save your own OpenAI API key. The key is stored in macOS Keychain and is never bundled with the app.
5. Click **Voice** once and allow microphone access. Joi connects, listens, and answers continuously; interrupt naturally while she is speaking. Click **Voice** again to end the session.
6. Start playback in your preferred source, then use Joi's transport controls. The first use may ask for Accessibility permission so Joi can send the standard macOS media keys. Joi resolves macOS's current Now Playing owner and refuses to send a key unless that exact source has active media output. The center button is intentionally **Pause** rather than resume, and owner detection fails closed if macOS cannot resolve it; these safeguards prevent Music from opening by accident. Native-only favorite, shuffle, or lyrics helpers may separately request Automation permission for Music or Spotify.

The universal DMG supports Apple Silicon and Intel Macs and requires macOS 14 or later.

## Focus timer

Click **Focus** to open the compact Clock-style card. Pick 15, 25, 30, or 45 minutes and press Start. The same Focus icon closes the card without cancelling an active timer. Reopen it to pause, resume, or reset the timer. Completion always plays a local alert with system-sound fallbacks, posts a notification banner when permitted, and triggers Joi's celebration animation.

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

This private-beta media-owner check loads macOS's current MediaRemote owner interface at runtime, with the legacy callback retained for macOS 14 and early macOS 15, because Apple does not expose an equivalent public owner-query API. Joi does not link against MediaRemote directly and disables media controls if neither runtime path is available. Replace this bridge with a public API before any Mac App Store distribution.
