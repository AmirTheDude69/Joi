# Security and privacy design

## Enforced in the beta

- Bearer authentication on every `/v1`, `/mcp`, and `/oauth` path.
- User ownership checks inside every in-memory collection.
- RLS policies in the PostgreSQL schema.
- External writes represented as expiring, idempotent approval records with exact payload previews.
- Destructive and financial risks rejected by policy.
- Sensitive trace payloads disabled in the Agents SDK runner.
- PWA credential isolation through a server-only proxy.
- Security response headers and no API caching in the PWA.
- Retrieved connector content explicitly marked as untrusted in prompts, tools, and skills.

## Required before public deployment

- Replace the demo bearer check with a verified OIDC provider and short-lived sessions; use OAuth PKCE for connectors.
- Use least-privilege Google scopes and encrypt refresh tokens with a separate KMS-backed key.
- Add CSRF protection, reauthentication for destructive account operations, approval replay protection, and server-side rate/spend limits.
- Back the domain service with PostgreSQL transactions, a durable job queue, encrypted object storage, and retention/deletion workers.
- Redact secrets and connector contents from structured logs, errors, analytics, and traces.
- Add moderation and crisis-resource routing with a documented human escalation policy.
- Run SAST, dependency review, secret scanning, cross-tenant integration tests, OAuth abuse tests, prompt-injection red-team cases, and an independent security review.

## Retention defaults

- Connector payload cache: at most seven days.
- Conversation history: 90 days by default.
- Explicit memory: until deletion or user-selected expiration.
- Audio: not collected in the text beta.
- Training: Joi product data must not be used for fine-tuning.

These targets are product requirements. The in-memory beta loses data on restart and therefore must not be described as implementing production retention.
