# Architecture

Source of truth for what is actually deployed. Keep this in sync with the droplet.

## Host

- DigitalOcean droplet `178.128.111.29`, region `sgp1`, Ubuntu 24.04 LTS, 2 GB / 1 vCPU.
- SSH alias `hermes-vps` → user `hermes`, key `~/.ssh/hermes_droplet` (per-droplet isolation).
- Hardened: `ufw` allows only 22/80/443; `fail2ban`; key-only SSH; Tailscale for a private route.

## Track A — Hermes Agent (primary)

```
Telegram ─┐
Discord  ─┼─▶ hermes gateway (systemd) ─▶ RTK terminal filter ─▶ provider: openai-codex ─▶ ChatGPT subscription (OAuth)
Web UI   ─┘                                                                                (no per-token API cost)
```

- Official `hermes-agent` v0.17.0, installed as user `hermes` (`~/.local/bin/hermes`, config `~/.hermes/`).
- `provider: "openai-codex"` in `~/.hermes/config.yaml`; authenticated via
  `hermes auth add openai-codex --type oauth --manual-paste`.
- Runtime invariant: `provider: "openai-codex"` must have a non-empty model. The deployed model is
  `openai/gpt-5.5`; `scripts/configure-model.sh` enforces it and `scripts/verify-runtime.sh` fails
  if provider/model/auth/services drift.
- Runtime invariant: `compression.enabled=true` keeps auto-compaction active, while
  `compression.codex_gpt55_autoraise=false` suppresses the repeated Codex context-cap notice in
  Telegram/Discord. `scripts/verify-runtime.sh` fails if either setting drifts.
- Runtime invariant: RTK (Rust Token Killer) is present and enabled through the `rtk-rewrite`
  Hermes plugin. `RTK_HERMES_MODE=rewrite` and `RTK_HERMES_BACKENDS=local` keep local noisy
  terminal commands compact by default; agents must bypass RTK and inspect raw logs when a
  summarized command hides context needed for critical debugging. `scripts/configure-rtk.sh` installs
  RTK, enables the plugin, writes non-secret RTK env defaults, and restarts Hermes services so the
  plugin is loaded.
- Messaging gateway runs Telegram + Discord concurrently; web UI via `hermes dashboard` (port 9119,
  password-protected on public bind).
- Allow-lists (`TELEGRAM_ALLOWED_USERS`, `DISCORD_ALLOWED_USERS`) restrict access — the agent has
  terminal/file tools, so this is a hard security requirement.

### Magang document extension

```
Natural-language work update ─▶ Hermes ─▶ magang CLI ─▶ YAML log ─▶ official DOCX ─▶ PDF
```

- The separate `magang-tool` application is deployed to `~/magang`; its shim is
  `~/.local/bin/magang`. Runtime `config.yaml`, daily logs, generated files, and official university
  DOCX templates are deliberately excluded from this public infrastructure repository.
- `scripts/configure-magang.sh` idempotently syncs application code while preserving
  `config.yaml`, `data/`, and `out/`; installs the Python environment and headless LibreOffice; and
  injects `infra/hermes-soul-magang.md` as a managed block in `~/.hermes/SOUL.md`.
- Hermes interprets conversational dates, times, and tasks. The CLI owns deterministic date/week
  storage, hour calculations, official template filling, and DOCX/PDF generation.
- `scripts/verify-magang.sh` proves the CLI, both official templates, LibreOffice renderer, config
  load, and persistent Hermes instruction block are present.

## Track B — Web dashboard (on the subscription)

```
Browser ─▶ Caddy (host net, TLS, basic-auth) ─▶ hermes dashboard 127.0.0.1:9119 ─▶ ChatGPT subscription
```

- Public HTTPS at `assistant.dafandikri.tech` (DNS at Cloudflare, **DNS-only / grey-cloud** so
  Caddy's HTTP-01 challenge works; orange-cloud proxy would break it).
- The web face is the **Hermes dashboard** (`hermes-dashboard.service`, systemd user unit), which
  runs on the same Codex subscription as the bots — **no API key, no separate admin account**.
- The dashboard binds loopback (its own DNS-rebinding guard rejects other Host headers), so:
  - Caddy runs `network_mode: host` to reach `127.0.0.1:9119`;
  - Caddy rewrites upstream `Host` and `Origin` to the loopback dashboard origin;
  - **Caddy basic-auth** gates the edge (the dashboard skips auth on loopback);
  - applied via `scripts/switch-to-dashboard.sh` (idempotent: swap → free RAM → build → service →
    render Caddyfile with bcrypt creds → reload Caddy → verify 401-then-200 → run the runtime guard).
- **Open WebUI** (the original Track B) stays defined in compose but is **stopped** (it needed a model
  API key; the subscription can't drive it). Reverting = restore the open-webui `Caddyfile` + bridge
  networking and `docker compose up -d open-webui`.

## Decision log

- **API/subscription over GPU self-hosting** — a GPU droplet (~$288/mo) would exhaust the ~$113
  credit in ~12 days; the app + subscription/API path lasts months.
- **`openai-codex` provider for the agent** — lets the bots run on an existing ChatGPT subscription
  with no per-token billing (personal-use OAuth; not for resale/multi-user).
- **nip.io → real domain** — bootstrapped on `nip.io` for instant TLS, then moved to
  `assistant.dafandikri.tech`.
- **Universal agent instructions** — `AGENTS.md` is canonical for Codex and other coding agents;
  `CLAUDE.md` and `OPENCODE.md` are thin entrypoints that point back to it. The gate validates this
  so future agents do not drift into conflicting instructions.
- **Mistake log as a guardrail** — production-impacting mistakes are recorded in
  [docs/operations/mistakes.md](operations/mistakes.md), and `scripts/validate-lessons.sh` fails the
  gate unless each lesson has impact, root cause, guardrail, and verification.
- **Current-design validation** — `scripts/validate-current-design.sh` fails the gate if docs and
  committed infra stop describing the deployed architecture (`openai-codex`, `openai/gpt-5.5`,
  auto-compression on, Codex auto-raise notice off, RTK terminal-output filtering, dashboard
  loopback, Caddy host networking, edge auth, Host/Origin rewrites, and the managed magang
  integration).
