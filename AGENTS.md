# AGENTS.md

Universal working instructions for coding agents in this repo. Codex loads this file directly.
Claude and opencode entrypoints should defer to it. Keep it compact and operational.

## Project

This repo is infrastructure-as-code for a self-hosted Hermes personal assistant on a
DigitalOcean droplet.

- Live repo: GitHub repo `dafandikri/hermes` (public by owner approval; never commit secrets).
- Live host: `hermes-vps` SSH alias, user `hermes`.
- Public web: `https://assistant.dafandikri.tech`.
- Primary runtime: official Hermes Agent on `openai-codex`, using the owner's ChatGPT/Codex
  subscription through OAuth.
- Channels: Telegram, Discord, WhatsApp, and the Hermes dashboard behind Caddy basic-auth. LINE
  integration and its public signed-webhook route are staged; activation requires rotated provider
  credentials.
- Optional old track: Open WebUI remains defined but stopped; it requires a model API key and is
  not the preferred subscription-powered path.

Read [docs/architecture.md](docs/architecture.md) before changing behavior.

## Non-Negotiables

- Do not commit secrets. Real values live only on the droplet (`/opt/hermes/.env`,
  `~/.hermes/.env`, both `chmod 600`) or provider dashboards.
- Do not print tokens, bot credentials, dashboard passwords, OAuth files, or private keys.
- Keep Cloudflare for `assistant.dafandikri.tech` as **DNS only / grey-cloud** unless you also
  implement DNS-01 ACME with a Cloudflare API token.
- Keep per-platform allow-lists mandatory for Telegram, Discord, LINE, and WhatsApp. The agent has
  terminal/file tools.
- For public web exposure, keep Caddy basic-auth in front of the dashboard.
- Keep the Hermes model invariant: provider `openai-codex`, model `openai/gpt-5.5`, auth logged in.
- Keep RTK (`rtk-rewrite`) enabled for noisy local terminal commands, but bypass it for raw logs
  whenever a failure needs full context.
- Prefer idempotent scripts in `scripts/` over ad-hoc SSH.
- Never rewrite git history, force-push, or change repo visibility without explicit user approval.

## Required Checks

Run before claiming code/config changes are done:

```bash
make gate
```

Run after any live infra/runtime change:

```bash
DASH_USER=admin DASH_PASS='<current-dashboard-password>' make verify-runtime HOST=hermes-vps
```

Run before/after bot or model changes:

```bash
make configure-model HOST=hermes-vps
make configure-rtk HOST=hermes-vps
make status HOST=hermes-vps
```

`make gate` covers formatting, shellcheck, YAML lint, infra validation, current-design validation,
agent-doc validation, mistake-log validation, and secret scanning. `make verify-runtime` proves the
live system is not a false green: model/provider, auto-compression on, Codex auto-raise notice off,
RTK plugin/binary, Codex auth, dashboard service, gateway service, and web edge auth must all pass.

## Common Commands

```bash
make help
make gate
make sast
make status HOST=hermes-vps
make verify-runtime HOST=hermes-vps
make dashboard HOST=hermes-vps
make configure-model HOST=hermes-vps
make configure-rtk HOST=hermes-vps
make configure-bots HOST=hermes-vps
make configure-line-edge HOST=hermes-vps
make pair-whatsapp HOST=hermes-vps
make verify-channels HOST=hermes-vps
```

## Editing Rules

- Shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, two-space indent, quote expansions.
- Source shared helpers from `scripts/lib.sh`.
- Secrets must flow via environment/stdin, never command argv.
- Keep scripts idempotent and fail-fast.
- Keep docs consistent with deployed reality. If the droplet differs from docs, update docs or
  fix the droplet before finishing.
- Keep committed infra consistent with docs. `scripts/validate-current-design.sh` is the guard for
  the current architecture: `openai-codex`, `openai/gpt-5.5`, auto-compression on, Codex auto-raise
  notice off, RTK terminal-output filtering, dashboard loopback, Caddy host networking, edge
  basic-auth, and Host/Origin rewrites.
- If a production mistake happens or repeats, update `docs/operations/mistakes.md` with impact,
  root cause, guardrail, and verification. Do not claim completion until the guardrail is automated
  or tied to a repo command.
- Use local `.semgrep.yml` rules; do not depend on moving remote Semgrep packs.

## Agent-Specific Notes

- **Codex:** uses this `AGENTS.md` as the project instruction file.
- **Claude Code:** reads `CLAUDE.md`, which is a shim pointing back here.
- **opencode:** use this `AGENTS.md` as the canonical project guide; `OPENCODE.md` points back here
  for tools that prefer a named opencode file.

If a tool-specific file conflicts with this one, treat this file as canonical and fix the drift.
