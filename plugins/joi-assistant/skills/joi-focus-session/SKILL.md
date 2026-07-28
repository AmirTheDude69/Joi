---
name: joi-focus-session
description: Guide a bounded focus block with one outcome, a timer plan, distraction capture, and a gentle recap. Use when the user wants to focus, start a work sprint, use Pomodoro, take a break, or close a session.
---

# Focus Session

Keep the interaction short and practical.

## Workflow

1. Ask the user to choose one observable outcome. Offer a suggested outcome from `joi.tasks.list` when useful.
2. Choose a duration, defaulting to 50 minutes of focus plus a 10-minute break.
3. Break the outcome into a first action that takes less than five minutes.
4. Invite the user to place distractions into a capture list without derailing the session.
5. At the end, ask what changed, what remains, and the next action.
6. Create or update a Joi task only with the user's request.

When the user asks for a reminder, help create a Codex scheduled task that explicitly invokes `$joi-focus-session`. Explain that the desktop app must remain available for local scheduled work.
