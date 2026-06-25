# Hermes — self-hosted personal assistant

A self-hosted AI personal assistant on a DigitalOcean droplet, powered by the
[Nous Research Hermes](https://github.com/NousResearch/hermes-agent) family.
Infrastructure-as-code, with an enforced quality gate.

This repository is safe to showcase publicly because secrets are kept out of git and enforced by
`gitleaks`. Operational details are intentionally documented; credentials are not.

## What's deployed

Two independent tracks share one hardened droplet (`sgp1`, Ubuntu 24.04, 2 GB):

| Track | You reach it via | Auth | Model billing |
| --- | --- | --- | --- |
| **Hermes Agent** | Telegram, Discord, LINE, WhatsApp | Your messaging identity (per-platform allowlists) | **Your ChatGPT subscription** (`openai-codex` provider, OAuth — no per-token cost); noisy terminal output goes through RTK |
| **Web dashboard** | `https://assistant.dafandikri.tech` (`hermes dashboard` behind Caddy) | Caddy basic-auth at the edge | **Same ChatGPT subscription** — no API key |
| Open WebUI *(stopped, revertable)* | — | — | would need a model API key; subscription can't drive it |

> **Why not self-host the weights?** Hermes is a frontier open model; running the
> 70B/405B needs a GPU (~$288/mo always-on). Hosting the *app* and reaching the
> model via subscription/API is the cost-sane choice. See
> [docs/architecture.md](docs/architecture.md).

## Repository layout

```
AGENTS.md     Canonical repo instructions for Codex, Claude, opencode, and other agents
CLAUDE.md     Claude Code shim that points to AGENTS.md
OPENCODE.md   opencode shim that points to AGENTS.md
infra/        Config-as-code: docker-compose.yml, Caddyfile, systemd unit, .env.example
scripts/      Idempotent ops scripts (deploy, configure, status, validate) + the gate
infra/hermes-soul-magang.md  Managed Hermes instructions for the external magang tool
docs/         Architecture, operations mistake log, and superpowers specs/plans
.github/      CI (the gate, strict)
Makefile      Developer entrypoint — run `make`
```

## Quickstart (development)

```bash
make setup     # install the toolchain (pre-commit, linters) + git hooks
make gate      # run THE quality gate
make sast      # local Semgrep rules
make status    # health-check the live droplet
make validate-current-design  # ensure docs and infra match the deployed design
make validate-lessons  # enforce the mistake log
```

## Operating the droplet

```bash
make deploy-webapp HOST=hermes-vps   # refresh the Caddy + Open WebUI stack
make status HOST=hermes-vps          # both tracks at a glance
make verify-runtime HOST=hermes-vps  # fail-fast live guard: model/auth/services/web gate
make verify-channels HOST=hermes-vps # messaging credentials, allowlists, sessions, health
make verify-magang HOST=hermes-vps   # verify internship logging + DOCX/PDF generation
make autopilot HOST=hermes-vps       # gate + SAST + model enforcement + runtime verify + status
```

The runtime guard is intentionally strict. If `openai-codex` is selected but the
model is blank, auth is logged out, the dashboard/gateway is down, or web auth no
longer blocks unauthenticated access, it fails instead of reporting a false green.
The active model is `openai/gpt-5.5`. Auto-compaction stays enabled
(`compression.enabled=true`), while the repeated Codex GPT-5.5 auto-raise notice stays suppressed
(`compression.codex_gpt55_autoraise=false`). RTK (Rust Token Killer) is installed and enabled via the
`rtk-rewrite` Hermes plugin so noisy terminal commands are summarized before they reach the
agent context; raw output remains the fallback for critical troubleshooting. `make configure-rtk`
installs/enables the plugin and restarts Hermes services so the hook is loaded.

Configuring Hermes messaging (secrets read from your environment, never argv):

```bash
make configure-model HOST=hermes-vps
make configure-rtk HOST=hermes-vps
export TELEGRAM_BOT_TOKEN=...  TELEGRAM_ALLOWED_USERS=<your-id>
export DISCORD_BOT_TOKEN=...   DISCORD_ALLOWED_USERS=<your-id>   # optional
scripts/configure-hermes.sh hermes-vps
```

### LINE

LINE uses its official Messaging API. Create a Provider and Messaging API channel in the LINE
Developers Console, issue a long-lived access token, and obtain your `U...` user ID. The webhook
route is the only unauthenticated route on the public domain; LINE validates every event with the
channel-secret signature. The dashboard remains behind Caddy basic-auth.

```bash
make configure-line HOST=hermes-vps
```

The command prompts for the token and secret with terminal echo disabled, so neither value enters
shell history. It also performs the equivalent of `make configure-line-edge`, installing the
signed webhook route before activating the adapter. If a credential is pasted into chat, an issue
tracker, or another log, revoke and regenerate it before running the command.

When prompted for the public URL, accept the default base origin
`https://assistant.dafandikri.tech`. Do not append `/line/webhook`; that suffix belongs only in the
LINE Developers webhook setting.

Set the LINE webhook URL to
`https://assistant.dafandikri.tech/line/webhook`, enable **Use webhook**, and disable LINE's
automatic greeting/reply messages.

### WhatsApp

Hermes's personal WhatsApp adapter uses the built-in Baileys bridge, which emulates WhatsApp Web.
It needs no Meta developer account, but it is unofficial and carries account-restriction risk.
Use a dedicated bot number, avoid unsolicited/bulk messages, and never commit
`~/.hermes/whatsapp/session`.

```bash
make pair-whatsapp HOST=hermes-vps  # interactive QR scan
export WHATSAPP_ENABLED=true
export WHATSAPP_MODE=bot
export WHATSAPP_ALLOWED_USERS=628... # country code, no leading +
make configure-bots HOST=hermes-vps
make verify-channels HOST=hermes-vps
```

For a production business number, use Hermes's official WhatsApp Business Cloud API adapter
instead; it requires Meta Business credentials and a separate public webhook route.

### Internship logging extension

Hermes can turn natural-language daily work updates into 20-SKS internship logs and generate the
official weekly Log Magang and Kerangka Acuan files as DOCX and PDF. The application, private
configuration, logs, and university templates live in the separate local `magang-tool` project;
this public repo owns its repeatable deployment and the managed instruction block injected into
`~/.hermes/SOUL.md`.

```bash
MAGANG_SOURCE="$HOME/Documents/Internship/Semester 7/magang-tool" \
  make configure-magang HOST=hermes-vps
make verify-magang HOST=hermes-vps
```

Deployment preserves remote `config.yaml`, `data/`, and `out/`. The managed SOUL block is replaced
idempotently without overwriting unrelated persona instructions.

## Quality gate

Every commit runs `pre-commit` (shellcheck, shfmt, yamllint, gitleaks, current-design validation,
agent-doc validation, mistake-log validation).
Every push runs the full gate locally. CI runs the same [`scripts/gate.sh`](scripts/gate.sh) in
strict mode plus Semgrep SAST on pushes, pull requests, manual dispatch, and a weekly schedule.
Dependabot opens weekly update PRs for GitHub Actions. See
[CONTRIBUTING.md](CONTRIBUTING.md).

Production mistakes are tracked in [docs/operations/mistakes.md](docs/operations/mistakes.md).
New production-impacting failures must add or update a lesson with root cause, guardrail, and a
verification command before the work is considered complete.

## Secrets

Secrets live only on the droplet (`/opt/hermes/.env`, `~/.hermes/.env`, both `chmod 600`)
and in provider dashboards — **never** in git. `infra/.env.example` is the template;
`gitleaks` enforces it.
