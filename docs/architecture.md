# Architecture

Source of truth for what is actually deployed. Keep this in sync with the droplet.

## Host

- DigitalOcean droplet `178.128.111.29`, region `sgp1`, Ubuntu 24.04 LTS, 2 GB / 1 vCPU.
- SSH alias `hermes-vps` → user `hermes`, key `~/.ssh/hermes_droplet` (per-droplet isolation).
- Hardened: `ufw` allows only 22/80/443; `fail2ban`; key-only SSH; Tailscale for a private route.

## Track A — Hermes Agent (primary)

```
Telegram ─┐
Discord  ─┼─▶ hermes gateway (systemd) ─▶ provider: openai-codex ─▶ ChatGPT subscription (OAuth)
Web UI   ─┘                                                          (no per-token API cost)
```

- Official `hermes-agent` v0.17.0, installed as user `hermes` (`~/.local/bin/hermes`, config `~/.hermes/`).
- `provider: "openai-codex"` in `~/.hermes/config.yaml`; authenticated via
  `hermes auth add openai-codex --type oauth --manual-paste`.
- Messaging gateway runs Telegram + Discord concurrently; web UI via `hermes dashboard` (port 9119,
  password-protected on public bind).
- Allow-lists (`TELEGRAM_ALLOWED_USERS`, `DISCORD_ALLOWED_USERS`) restrict access — the agent has
  terminal/file tools, so this is a hard security requirement.

## Track B — Open WebUI (optional web app)

```
Browser ─▶ Caddy (TLS, Let's Encrypt) ─▶ Open WebUI ─▶ OpenAI-compatible API (OpenRouter/OpenAI)
```

- `docker compose` stack in `/opt/hermes` (`caddy` + `open-webui`), `restart: unless-stopped`.
- Public HTTPS at `assistant.dafandikri.tech` (DNS at Cloudflare, **DNS-only / grey-cloud** so
  Caddy's HTTP-01 challenge works; orange-cloud proxy would break it).
- Requires a model API key in `/opt/hermes/.env` — a ChatGPT subscription cannot drive Open WebUI.

## Decision log

- **API/subscription over GPU self-hosting** — a GPU droplet (~$288/mo) would exhaust the ~$113
  credit in ~12 days; the app + subscription/API path lasts months.
- **`openai-codex` provider for the agent** — lets the bots run on an existing ChatGPT subscription
  with no per-token billing (personal-use OAuth; not for resale/multi-user).
- **nip.io → real domain** — bootstrapped on `nip.io` for instant TLS, then moved to
  `assistant.dafandikri.tech`.
