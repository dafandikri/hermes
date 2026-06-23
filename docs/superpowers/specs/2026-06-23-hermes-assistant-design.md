# Hermes Personal Assistant on DigitalOcean — Design Spec

**Date:** 2026-06-23
**Author:** dafandikri (with Claude)
**Status:** Superseded in part — see revision note. Current truth: [../../architecture.md](../../architecture.md)

## Revision 2026-06-23 — as-built divergence

This spec captured the original single-track design (Open WebUI + OpenRouter). The build
evolved into **two tracks** as requirements grew (multi-channel + zero per-token cost):

- **Track A — official Hermes Agent** (Telegram + Discord + `hermes dashboard`), running on the
  owner's **ChatGPT subscription** via the `openai-codex` provider (no per-token API cost). This
  is now the primary assistant.
- **Track B — Open WebUI** (this spec's original design) remains deployed as an optional web app
  at `assistant.dafandikri.tech`; it needs a model API key (a subscription cannot drive it).

Sections 2–11 below describe Track B and remain accurate for it. For the full current
architecture and decision log, see [docs/architecture.md](../../architecture.md).

## 1. Goal

Stand up a private, always-on personal assistant on a DigitalOcean VPS, powered
by the **Nous Research Hermes 4** model, reachable over public HTTPS on the
owner's own domain. Optimize for a fixed **$113.18** DigitalOcean credit so it
lasts months, not days.

## 2. Key Decision: API-backed, not weight-hosted

Hermes 4 is a raw open-weight LLM family (14B / 70B / 405B, Llama 3.1 based,
released 2025-08-30). Self-hosting the weights needs a GPU. DigitalOcean's
cheapest GPU (RTX 4000 Ada, $0.40/hr) is **~$288/mo always-on** — it would burn
the $113 credit in ~12 days.

**Therefore the model runs in the cloud via OpenRouter**, and only a small
assistant app runs on the Droplet. This delivers the best Hermes model (70B/405B)
at full speed for pennies, while the credit covers the Droplet for ~9 months.

- Model: `nousresearch/hermes-4-70b` via OpenRouter
- Price: **$0.13 / M input tokens, $0.40 / M output tokens** (heavy personal use ≈ a few $/mo)
- 405B (`nousresearch/hermes-4-405b`) selectable later for harder tasks

## 3. Architecture

```
You (browser / phone)
      │  HTTPS (your domain, Let's Encrypt)
      ▼
┌──────────────────────────────────────────────┐
│  DigitalOcean Droplet                          │  Ubuntu 24.04 LTS, 2GB/1vCPU (~$12/mo)
│  ┌────────────────┐      ┌──────────────────┐ │
│  │ Caddy (TLS,    │ ───▶ │ Open WebUI        │ │  Docker Compose
│  │ auto Let's     │      │ (assistant + UI)  │ │
│  │ Encrypt)       │      └─────────┬─────────┘ │
│  └────────────────┘                │           │
└────────────────────────────────────┼───────────┘
                                     │ OpenAI-compatible API call
                                     ▼
                          OpenRouter → Nous Hermes 4 70B
```

## 4. Components

| Component | Choice | Why |
|---|---|---|
| Host | DigitalOcean Droplet, Ubuntu 24.04 LTS, **2GB RAM / 1 vCPU / 50GB SSD** | Open WebUI runs comfortably; ~$12/mo from credit ≈ 9 months |
| Container runtime | Docker + Docker Compose v2 | Reproducible, single-file stack |
| Assistant app | **Open WebUI** | Most popular self-hosted AI chat; OpenAI-compatible; chat history, RAG, tools, multi-user. Alt: LibreChat |
| Reverse proxy / TLS | **Caddy 2** | Automatic Let's Encrypt certs + renewal, tiny config |
| Model access | **OpenRouter** (`nousresearch/hermes-4-70b`) | No GPU; best Hermes at low per-token cost |
| Access | Public HTTPS on owner's **domain** + **Tailscale** private route | User-chosen: public web for use, Tailscale as a private admin fallback |

Each component has one job and a clear interface: Caddy terminates TLS and proxies
to Open WebUI; Open WebUI owns the chat experience and persistence; OpenRouter is
the model backend behind an OpenAI-compatible URL. Any one can be swapped without
touching the others (e.g. Open WebUI → LibreChat, or OpenRouter → a future
self-hosted vLLM endpoint).

## 5. Data flow

1. User opens `https://assistant.<yourdomain>` → Caddy serves TLS, proxies to Open WebUI.
2. User sends a message → Open WebUI calls `https://openrouter.ai/api/v1/chat/completions`
   with the API key and model `nousresearch/hermes-4-70b`.
3. OpenRouter routes to Hermes 4 70B; tokens stream back through Open WebUI to the browser.
4. Conversation persisted locally in Open WebUI's SQLite volume on the Droplet.

## 6. Configuration (the important env)

Stored in `/opt/hermes/.env` (chmod 600, never committed):

```
OPENAI_API_BASE_URL=https://openrouter.ai/api/v1
OPENAI_API_KEY=sk-or-...           # OpenRouter key (test/placeholder until provisioned)
DEFAULT_MODELS=nousresearch/hermes-4-70b
WEBUI_AUTH=true
ENABLE_SIGNUP=false                # after the first admin account is made
DOMAIN=assistant.example.com       # replace with real domain
```

## 7. Security (public-facing, non-negotiable)

- `ufw`: allow **22 (SSH), 80, 443** only; deny all other inbound. Tailscale (`tailscale0`) is allowed for private access.
- SSH hardening: key-only auth, disable root password login, install **fail2ban**.
- **Tailscale**: installed on the Droplet and joined to the owner's tailnet, giving a private
  admin route (SSH and, optionally, Open WebUI) that works even if the public path is locked
  or DNS breaks. Optional hardening later: restrict SSH (port 22) to the tailnet only and drop
  it from `ufw` public rules once Tailscale is confirmed working.
- Caddy auto-HTTPS (HTTP→HTTPS redirect, HSTS).
- Open WebUI: create admin account on first boot, then **set `ENABLE_SIGNUP=false`**.
  Optional extra gate: Caddy **basic-auth** in front of the app.
- OpenRouter: set an **account spending limit / credit cap** so a runaway loop can't drain funds.
- Secrets only in `.env` (600) and OpenRouter dashboard — never in the image or git.

## 8. Backup & cost control

- Weekly **DO snapshot** of the Droplet (covers Open WebUI SQLite + config).
- DO **billing alert** at e.g. $50 and $90 of the $113 credit.
- OpenRouter hard spend limit (e.g. $10/mo) as a second guardrail.

## 9. Verification (definition of done)

1. `docker compose ps` shows `caddy` and `open-webui` healthy.
2. `curl` to OpenRouter with the key returns HTTP 200 and a completion.
3. `https://assistant.<domain>` loads with a valid (green) certificate.
4. A chat message returns a streamed Hermes 4 reply.
5. Public IP:80 redirects to HTTPS; no other ports are open (`nmap`/`ufw status`).
6. Reboot the Droplet → stack auto-starts (Compose `restart: unless-stopped`).
7. `tailscale status` shows the Droplet online; SSH over the Tailscale IP succeeds.

## 10. Out of scope (YAGNI for v1)

- Self-hosting Hermes weights on a GPU (documented as a future optional learning track).
- Multi-user / team features, SSO.
- Voice, mobile app wrappers, custom agent tool-chains — add later if wanted.

## 11. Open follow-ups

- Owner must have/register a **domain** and point an A record at the Droplet IP.
- Owner must create an **OpenRouter account** + API key and add a few dollars of credit.
