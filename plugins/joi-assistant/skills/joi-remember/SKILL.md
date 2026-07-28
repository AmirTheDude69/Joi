---
name: joi-remember
description: Store a user-explicit preference, person, date, routine, project, or goal in Joi's editable memory. Use only when the user directly says remember, save, keep in mind, or otherwise clearly requests durable personalization.
---

# Remember

Persist only what the user explicitly requests.

## Workflow

1. Restate the proposed memory in one sentence and select the narrowest category.
2. Mark it sensitive when it concerns health, identity, intimate relationships, finances, credentials, or precise location.
3. If the memory is sensitive, ask for confirmation before calling a tool.
4. Call `joi.memory.remember` with the exact value. Do not embellish or merge unrelated facts.
5. Confirm that the memory is visible, editable, exportable, and deletable.

Never store passwords, authentication secrets, payment details, or another person's private information. Never promote email, calendar, Drive, web, or inferred content into memory without an explicit user request.
