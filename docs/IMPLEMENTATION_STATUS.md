# Implementation status

## Delivered foundation

- Shared TypeScript workspace, contracts, agent service, MCP server, and PWA.
- OpenAI Agents SDK manager with planning, research, communications, memory, and document specialists.
- Safe deterministic demo mode and mock Google connectors for local verification.
- Action-risk policy, idempotent exact-preview approvals, audit history, and cross-user in-memory isolation.
- Explicit memory, task, automation, profile, connector, capability, export, and deletion endpoints.
- PostgreSQL/pgvector migration with row-level tenant policies and queue-ready automation fields.
- Codex plugin manifest, ten skills, local MCP configuration, pet assets, and macOS/Linux/Windows installer scripts.
- PWA chat, state-synchronized avatar, 16-direction gaze, tasks, memory, approval inbox, automation templates, settings, responsive layout, service worker, and reduced motion.
- Universal native macOS companion with a draggable floating avatar, six-position glass radial menu, silent ChatGPT Voice browser handoff, Pomodoro with active/archive tasks, browser search, Codex switching, real-time Music/Spotify controls, launch-at-login, and reduced motion.
- Capability flags distinguish implemented beta behavior from planned MVP release gates, preventing unavailable features from being enabled.

## Deliberate launch gates

These cannot be honestly completed from source code alone and remain disabled or mocked:

- Signed likeness/derivative-use release and trademark/name clearance.
- Counsel-approved and hosted privacy policy, terms, acceptable-use policy, and deletion policy.
- Production identity provider, social login, OAuth PKCE, session management, reauthentication, and tenant claims.
- Real Gmail, Calendar, Drive, and Docs adapters plus encrypted token rotation/revocation.
- PostgreSQL repository adapter, encrypted object storage, durable job worker, push delivery, and retention sweeper.
- Subscription billing, metering, budgets, support/admin console, and production entitlements.
- Full image/PDF/file ingestion, web research, spreadsheets, and document generation through the standalone product.
- Moderation operations, crisis routing, independent penetration test, privacy review, and 95% eval target evidence.
- Public deployment, domain, monitored infrastructure, backups, incident response, and service-level targets.
- Production voice brokering with ephemeral credentials, public voice safety/retention operations, ChatGPT app, non-macOS native shells, custom avatars, couple/family spaces, and marketplace features.

## Milestone mapping

| Milestone | Status | Notes |
| --- | --- | --- |
| 0 — Rights and product specification | Blocked on human/legal approval | Drafts and checklist provided; no approval is claimed. |
| 1 — Agent-core prototype | Implemented | Real OpenAI path plus deterministic demo and tests. |
| 2 — Private Codex plugin | Implemented for local beta | Hosted OAuth and real Google connectors remain gated. |
| 3 — Public plugin beta | Foundation only | Auth, billing, support, and security review required. |
| 4 — Web/PWA beta | Runnable local beta | Production accounts, push, persistence, and billing required. |
| 5 — Voice | Private macOS beta | The app performs a credential-free ChatGPT browser handoff; a native Realtime session still requires production ephemeral-credential brokering and safety/retention operations. |
| 6 — Custom companions | Disabled | Consent and moderation pipeline required first. |

## Go-live rule

The product must not be marketed as publicly launched until every Milestone 0 blocker and all high-severity security, privacy, identity, connector, deletion, and billing gates are closed with evidence.
