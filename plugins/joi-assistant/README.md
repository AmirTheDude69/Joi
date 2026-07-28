# Joi Assistant Codex plugin

The plugin bundles Joi's workflows, MCP connection, pet assets, and user-controlled installers. It points to the local beta server at `http://127.0.0.1:8787/mcp`; replace that URL with the production OAuth MCP endpoint only after the release gates are complete.

## Install from GitHub

1. Install Node.js 22+, enable Corepack, and clone the repository:

   ```bash
   git clone https://github.com/TheDudeCommits/Joi.git
   cd Joi
   corepack enable
   pnpm install
   cp .env.example .env
   ```

2. Start the local agent:

   ```bash
   pnpm dev:agent
   ```

3. Make the local beta token available to the Codex desktop process.

   macOS:

   ```bash
   launchctl setenv JOI_DEV_AUTH_TOKEN demo-user
   ```

   Windows PowerShell:

   ```powershell
   setx JOI_DEV_AUTH_TOKEN "demo-user"
   ```

   On Linux, launch Codex from a session that exports `JOI_DEV_AUTH_TOKEN=demo-user`.

4. Add the repository marketplace and install the plugin:

   ```bash
   codex plugin marketplace add TheDudeCommits/Joi --ref main
   codex plugin add joi-assistant@joi
   ```

5. Install the bundled pet.

   macOS/Linux:

   ```bash
   ./plugins/joi-assistant/scripts/install-pet.sh
   ```

   Windows:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\plugins\joi-assistant\scripts\install-pet.ps1
   ```

6. Completely restart Codex. Open `/mcp` and confirm that `joi` is connected. Start a new task and run `$joi-setup`.

## Install from a local checkout

From the repository root:

```bash
codex plugin marketplace add "$PWD"
codex plugin add joi-assistant@joi
```

If that marketplace is already configured, use `codex plugin marketplace upgrade joi` for a Git source, or reinstall the plugin after updating the local cachebuster.

## Included skills

- `$joi-plan-my-day`
- `$joi-inbox-brief`
- `$joi-schedule`
- `$joi-focus-session`
- `$joi-meeting-prep`
- `$joi-weekly-review`
- `$joi-relationship-idea`
- `$joi-remember`
- `$joi-setup`
- `$joi-troubleshoot`

Ready-to-adapt background prompts are in `assets/scheduled-task-templates.md`. Test a prompt in a normal task before scheduling it, and keep unattended permissions narrow.

Read tools are automatic. MCP tools that are not marked read-only prompt by default, and email/calendar request tools are explicitly approval-gated. The backend itself also creates a second exact-preview approval record before any external action can execute.

## Production deployment

The checked-in `.mcp.json` is a local development profile. A hosted build must use HTTPS, OAuth with PKCE, per-user tenant identity, minimum Google scopes, encrypted refresh tokens, and a production approval center. Never publish `demo-user` as a production credential.
