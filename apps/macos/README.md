# Joi for macOS

Joi for macOS is a separate floating companion app. Click the avatar to reveal six controls in a circular AssistiveTouch-style layout:

- 12 o'clock: open ChatGPT Voice in the default browser.
- Top right: quick Google search in the default browser.
- Bottom right: compact Focus timer.
- 6 o'clock: Settings.
- Bottom left: open or switch to Codex.
- Top left: an icon-only watchOS-style media honeycomb for previous, pause, next, favorite, shuffle, and lyrics. Transport targets the validated current macOS Now Playing source instead of defaulting to Apple Music. Shuffle and Favorite use capability-gated player commands, plus a local Spotify Web control when Arc owns the current session.

The primary actions are frameless SF Symbols with generous invisible hit targets, including the hollow center of Search. Every native button uses the supplied Framer University Magnetic Hover defaults through a source-faithful SwiftUI adapter. Search, Focus, and Voice keep their selected control visible; click that same control again to close Joi's local card. Inactive controls close after 15 seconds by default, and the timeout is adjustable from 5–60 seconds in Settings. Voice cannot stop or inspect the separate ChatGPT browser session. Drag the avatar to move Joi with screen-space tracking, or right-click it and choose **Close Joi** to exit the app. The companion stays above other windows by default, can be resized from 70–140% in Settings, and has a small menu-bar item for Show, Settings, and Quit.

## Install from the DMG

1. Open `Joi-0.6.0-macOS-Universal.dmg`.
2. Drag **Joi** to **Applications**.
3. This private-beta build is ad-hoc signed rather than Apple-notarized. On first launch, Control-click Joi in Applications, choose **Open**, then confirm **Open**.
4. Click Joi, choose **Settings**, and use **Avatar size** to choose 70–140%. The transparent companion window and drag target resize with the avatar.
5. Click **Voice**. Joi opens `chatgpt.com` in the default browser. Select ChatGPT's Voice icon once and allow microphone access, then return to your apps. ChatGPT requires that browser interaction; Joi cannot safely auto-click it. Choose **Maple** in ChatGPT's voice settings for the closest cheerful/candid match. If ChatGPT offers Background Conversations for your account, enable that in ChatGPT settings.
6. Start playback in your preferred source, then use Joi's transport controls. Joi sends previous/play-pause/next to the validated current Now Playing session. If the small shield or retry icon appears, enable the installed `/Applications/Joi.app` in System Settings → Privacy & Security → Accessibility and retry. Favorite and Shuffle in Spotify Web use the already-open `open.spotify.com` tab only when Arc owns Now Playing; macOS may ask once for permission to let Joi automate Arc. Native Music or Spotify helpers may likewise request Automation permission. Joi never opens Apple Music as a fallback.

The universal DMG supports Apple Silicon and Intel Macs and requires macOS 14 or later.

## Focus timer

Click **Focus** to open the compact Clock-style card. Pick 15, 25, 30, or 45 minutes and press Start. Add up to ten local tasks beneath Reset and Start, check them off, or remove them; the checklist persists across launches. The same Focus icon closes the card without cancelling an active timer. Reopen it to pause, resume, or reset the timer. Completion always plays a local alert with system-sound fallbacks, posts a notification banner when permitted, and triggers Joi's celebration animation.

## Avatar animation map

The standalone app uses all standard rows in the canonical v2 spritesheet:

| Rows | Animation | Attached events and behavior |
| --- | --- | --- |
| 0 | Idle | Static baseline plus ambient breathing, blink, and wink. The ambient scheduler rotates through Idle, Wave, Review, Waiting, and Jump gestures every 4.5–8 seconds instead of looping one strip continuously. |
| 1 | Run right | Radial menu opening. |
| 2 | Run left | Radial menu closing, including the inactivity timeout, unless an active Focus context has priority. |
| 3 | Wave | Successful previous/play-pause/next/shuffle/lyrics actions, a completed checklist item, greetings, ambient variety, and the final half of celebrations. |
| 4 | Jump | Successful Favorite, Focus completion, all checklist items completed, ambient variety, then Wave. |
| 5 | Failed | ChatGPT browser handoff failure or an unavailable/failed music action. |
| 6 | Waiting | Successful ChatGPT Voice handoff, paused Focus, and ambient variety. Long-lived Waiting alternates with Review and quiet Idle rests. |
| 7 | Working | A running Focus timer, alternating naturally with Review and quiet Idle rests. It continues even when the controls auto-close. |
| 8 | Review | Search, Settings, adding a Focus task, ambient variety, and the thoughtful variant inside Waiting/Working contexts. |
| 9–10 | 16 look directions | Pointer attention while Joi is otherwise idle: up, clockwise intermediates, right, down, left, and back to up, with a 24-point center dead zone. |
| Standalone dance frames | Dance / vibe | Starts automatically when Joi detects active music from the current supported macOS playback source, including Spotify in Arc. Voice, Focus, Search, and explicit success/failure gestures temporarily take priority; dancing resumes afterward while playback continues. Two missed playback samples are required before returning to Idle, preventing flicker between tracks. |

Reduce Motion in Settings disables cycling and pointer-gaze movement. When music is playing with Reduce Motion enabled, Joi holds the first dance pose instead of looping.

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

## ChatGPT Voice handoff

Joi opens the official ChatGPT website and does not capture microphone audio, hold an OpenAI API key, or claim that it started listening. ChatGPT itself controls voice availability, microphone permission, transcripts, data controls, limits, and any Background Conversations option. The consumer website has no supported deep link that starts Voice, so the user must select ChatGPT's Voice icon once in the browser. A genuinely one-click native conversation requires a separate Realtime API session with server-minted ephemeral credentials; see OpenAI's [voice-agent guide](https://developers.openai.com/api/docs/guides/voice-agents#build-a-speech-to-speech-voice-agent) and [WebRTC credential guide](https://developers.openai.com/api/docs/guides/realtime-webrtc#creating-an-ephemeral-token).

If an older Joi version stored an API key, Settings offers a one-click removal of that unused legacy Keychain item.

## Codex activity boundary

The public Codex app-server protocol can power a separate client and stream events for Codex tasks that client starts or resumes. It does not expose the existing Codex desktop app's private, cross-task pet activity tray to an unrelated process. Joi therefore opens Codex but does not claim to mirror every desktop task's Running, Needs input, Ready, or Blocked state. An optional future Codex bridge can map app-server events for Joi-managed tasks, but it would not be an exact mirror of all activity already running inside the Codex app.

This private-beta media bridge loads macOS's current MediaRemote owner and transport interfaces at runtime, with guarded fallbacks, because Apple does not expose equivalent public APIs for controlling another app's Now Playing session. Joi does not link against MediaRemote directly and fails closed if it cannot validate or command the current source. Replace this bridge with a public approach before any Mac App Store distribution.

The verbatim supplied Framer source is retained at `Reference/MagneticHover.framer.tsx`. Because React/Framer can transform browser DOM elements only, `MagneticHover.swift` is the native adapter used by the app; it preserves the supplied distance, expanded hover area, smoothing-to-stiffness mapping, damping, normalization, and reset behavior without replacing native controls with a web view.
