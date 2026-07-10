---
name: joi-troubleshoot
description: Diagnose Joi plugin installation, pet visibility, MCP connectivity, authentication, tool approval, PWA, and agent-service failures. Use when Joi is missing, offline, unauthenticated, stuck, failing a tool, or showing stale plugin content.
---

# Joi Troubleshoot

Diagnose before changing configuration. Never print secrets.

## Checks

1. Run `pnpm check` from the repository root and preserve the first actionable failure.
2. Verify `GET /health` on the agent service and confirm whether it reports demo or OpenAI mode.
3. Use `codex plugin list` and `/mcp` to check whether the expected marketplace, plugin version, and `joi` server are loaded.
4. For stale local content, run the plugin cachebuster helper, reinstall from the confirmed local marketplace, restart Codex, and test in a new task.
5. For pet issues, verify `~/.codex/pets/joi/pet.json` and `spritesheet.webp`, then validate that the atlas is 1536 by 2288 pixels.
6. For authorization failures, check environment-variable presence without revealing values. Production OAuth is a release gate in this beta.
7. For tool failures, inspect the visible audit entry and distinguish blocked policy, expired approval, connector failure, and server error.

Do not weaken write approvals, enable destructive or financial tools, or bypass identity checks as a troubleshooting shortcut.
