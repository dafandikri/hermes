# Hermes — self-hosted personal assistant

A self-hosted AI personal assistant on a DigitalOcean droplet, powered by the
[Nous Research Hermes](https://github.com/NousResearch/hermes-agent) family.
Infrastructure-as-code, with an enforced quality gate.

## What's deployed

Two independent tracks share one hardened droplet (`sgp1`, Ubuntu 24.04, 2 GB):

| Track | You reach it via | Auth | Model billing |
| --- | --- | --- | --- |
| **Hermes Agent** | Telegram, Discord | Your messaging identity (allow-listed user IDs) | **Your ChatGPT subscription** (`openai-codex` provider, OAuth — no per-token cost) |
| **Web dashboard** | `https://assistant.dafandikri.tech` (`hermes dashboard` behind Caddy) | Caddy basic-auth at the edge | **Same ChatGPT subscription** — no API key |
| Open WebUI *(stopped, revertable)* | — | — | would need a model API key; subscription can't drive it |

> **Why not self-host the weights?** Hermes is a frontier open model; running the
> 70B/405B needs a GPU (~$288/mo always-on). Hosting the *app* and reaching the
> model via subscription/API is the cost-sane choice. See
> [docs/architecture.md](docs/architecture.md).

## Repository layout

```
infra/        Config-as-code: docker-compose.yml, Caddyfile, systemd unit, .env.example
scripts/      Idempotent ops scripts (deploy, configure, status, validate) + the gate
docs/         Architecture + superpowers specs/plans
.github/      CI (the gate, strict)
Makefile      Developer entrypoint — run `make`
```

## Quickstart (development)

```bash
make setup     # install the toolchain (pre-commit, linters) + git hooks
make gate      # run THE quality gate (format, shellcheck, yaml, validate, secrets)
make status    # health-check the live droplet
```

## Operating the droplet

```bash
make deploy-webapp HOST=hermes-vps   # refresh the Caddy + Open WebUI stack
make status HOST=hermes-vps          # both tracks at a glance
make verify-runtime HOST=hermes-vps  # fail-fast live guard: model/auth/services/web gate
```

The runtime guard is intentionally strict. If `openai-codex` is selected but the
model is blank, auth is logged out, the dashboard/gateway is down, or web auth no
longer blocks unauthenticated access, it fails instead of reporting a false green.

Configuring the Hermes Agent bots (secrets read from your environment, never argv):

```bash
make configure-model HOST=hermes-vps
export TELEGRAM_BOT_TOKEN=...  TELEGRAM_ALLOWED_USERS=<your-id>
export DISCORD_BOT_TOKEN=...   DISCORD_ALLOWED_USERS=<your-id>   # optional
scripts/configure-hermes.sh hermes-vps
```

## Quality gate

Every commit runs `pre-commit` (shellcheck, shfmt, yamllint, gitleaks). CI runs the
same [`scripts/gate.sh`](scripts/gate.sh) in strict mode plus semgrep SAST. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Secrets

Secrets live only on the droplet (`/opt/hermes/.env`, `~/.hermes/.env`, both `chmod 600`)
and in provider dashboards — **never** in git. `infra/.env.example` is the template;
`gitleaks` enforces it.
