# CLAUDE.md — working in this repo

Project-specific guidance for AI agents. Global preferences still apply.

## What this is

Infrastructure-as-code for a self-hosted Hermes personal assistant on a DigitalOcean droplet.
Bash + YAML + Docker + Caddy. No application source — do not scaffold a Node/TS app here.
Read [docs/architecture.md](docs/architecture.md) first; it is the source of truth.

## Non-negotiables

- **Run the gate before claiming done:** `make gate` must print `✅ GATE PASSED`. It is
  [`scripts/gate.sh`](scripts/gate.sh) — the single source of truth, mirrored by CI.
- **Run live verification after deploy changes:** `make verify-runtime HOST=hermes-vps` must pass.
  A service being "active" is not enough; provider/model/auth/dashboard/gateway invariants must hold.
- **Never commit secrets.** Real values live only on the droplet (`/opt/hermes/.env`,
  `~/.hermes/.env`, `chmod 600`) and in provider dashboards. Repo carries only
  `infra/.env.example` placeholders; `gitleaks` will block leaks.
- **Secrets flow via environment/stdin, never argv** (avoids leaking into remote `ps`).
- **Allow-lists are mandatory** for any messaging gateway — the agent has terminal/file tools.
- **Cloudflare DNS stays grey-cloud (DNS only)** or Caddy's ACME HTTP-01 challenge breaks.
- **Git:** never commit/push without explicit instruction.

## Shell style

`#!/usr/bin/env bash`, `set -euo pipefail`, 2-space indent, quote expansions, source helpers from
[`scripts/lib.sh`](scripts/lib.sh). Scripts are idempotent and refuse on missing prerequisites.

## Where things are

- `infra/` — compose, Caddyfile, systemd unit, `.env.example`
- `scripts/` — `gate.sh`, `deploy-webapp.sh`, `configure-model.sh`, `configure-hermes.sh`,
  `verify-runtime.sh`, `status.sh`, `validate-config.sh`, `lib.sh`
- `docs/superpowers/` — specs + plans (keep reconciled with reality)
