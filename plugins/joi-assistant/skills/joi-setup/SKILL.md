---
name: joi-setup
description: Configure the Joi Codex plugin, local agent service, pet assets, MCP authentication, and optional scheduled-task prompts. Use for first installation, connection setup, pet installation, local development, or upgrade checks.
---

# Joi Setup

Set up the smallest safe configuration and explain every credential or permission requested.

## Local Beta

1. From the repository root, run `pnpm install`, copy `.env.example` to a local `.env`, and keep it uncommitted.
2. Start the agent with `pnpm dev:agent`; verify `http://127.0.0.1:8787/health`.
3. Start the PWA with `pnpm dev:web` when needed.
4. Run the user-controlled pet installer in `scripts/install-pet.sh` on macOS/Linux or `scripts/install-pet.ps1` on Windows.
5. Install the repo-local marketplace and plugin using the commands in the plugin README.
6. Restart Codex, open `/mcp`, and confirm the `joi` server and its tools are visible.

## Production Gate

Do not describe the beta bearer token as production authentication. Public release requires OAuth with PKCE, tenant isolation, encrypted connector credentials, hosted legal pages, likeness consent, trademark clearance, and real Google connector implementations.

Offer scheduled-task templates only after the corresponding skill succeeds manually. External writes must still stop for approval.
