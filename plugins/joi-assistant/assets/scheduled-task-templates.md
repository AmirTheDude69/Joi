# Scheduled-task templates

Test each prompt manually before scheduling it. Scheduled tasks run unattended, so keep permissions narrow. External writes must stop at an approval request.

## Weekday morning brief

Schedule: weekdays at 8:00 AM in the user's timezone.

```text
Use $joi-plan-my-day and $joi-inbox-brief to prepare a concise morning brief. Read only. Include fixed commitments, conflicts, three priorities, and urgent inbox threads. Do not draft or send messages and do not change the calendar.
```

## Focus-start nudge

Schedule: weekdays at the preferred focus start.

```text
Use $joi-focus-session to ask me to choose one observable outcome and begin a 50-minute focus block. Keep the nudge to three sentences and do not modify tasks unless I reply and ask.
```

## End-of-session recap

Schedule: weekdays near the end of working hours.

```text
Use $joi-focus-session to ask what I completed, what remains, and the next action. Do not infer completion from calendar or email activity.
```

## Weekly review

Schedule: Friday at 4:00 PM.

```text
Use $joi-weekly-review to summarize completed and open Joi tasks, upcoming calendar pressure, wins, friction, and at most three priorities. Read only unless I explicitly ask to capture a task.
```
