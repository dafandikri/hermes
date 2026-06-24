# Hermes Personal Assistant on DigitalOcean — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Note:** This is an infrastructure runbook. "Tests" are verification commands with expected output. Most steps run on your **local machine** or **over SSH on the Droplet** — each step says which. Commands marked `[droplet]` run on the server; `[local]` run on your laptop.

**Goal:** Stand up an always-on, public-HTTPS personal assistant on a DigitalOcean Droplet, powered by Nous Hermes 4 70B via OpenRouter, with SSH + Tailscale admin access.

**Architecture:** A small ($12/mo) Ubuntu 24.04 Droplet runs Docker Compose with two containers — Caddy (TLS via Let's Encrypt) reverse-proxying to Open WebUI (the assistant). Open WebUI calls the Hermes 4 model through OpenRouter's OpenAI-compatible API, so no GPU is needed. The config files live in this repo as infrastructure-as-code and are copied to the server.

**Tech Stack:** DigitalOcean Droplet, Ubuntu 24.04 LTS, Docker + Compose v2, Caddy 2, Open WebUI, Tailscale, OpenRouter.

> **As-built status (2026-06-23):** Tasks 1–9 (provision → hardening → Docker → Tailscale → IaC →
> deploy → first-run → backups) are **DONE**. The droplet is live: Open WebUI + Caddy serving
> HTTPS at `assistant.dafandikri.tech`. A **second track was added** — the official Hermes Agent
> (Telegram/Discord/dashboard) on the `openai-codex` provider (ChatGPT subscription). The
> ad-hoc SSH steps below are now superseded by idempotent scripts in `scripts/` (`deploy-webapp.sh`,
> `configure-hermes.sh`, `configure-rtk.sh`, `status.sh`) gated by `make gate`. Remaining manual steps are owner-only:
> Codex OAuth login, creating the Telegram/Discord bots, and (Track B) the Open WebUI admin account
> + API key. See [docs/architecture.md](../../architecture.md).

## Global Constraints

- Droplet size: **2GB RAM / 1 vCPU / 50GB SSD**, Ubuntu 24.04 LTS.
- Model: **`nousresearch/hermes-4-70b`** via base URL **`https://openrouter.ai/api/v1`**.
- Open ports (public): **22, 80, 443** only. Everything else denied by `ufw`.
- Secrets live only in `/opt/hermes/.env` on the Droplet (chmod 600) and the OpenRouter dashboard — **never committed to git**.
- Config files (`docker-compose.yml`, `Caddyfile`, `.env.example`) live in `infra/` in this repo.
- Total budget: **$113.18** DO credit. Set billing alerts and an OpenRouter spend cap.
- **SSH key: dedicated `~/.ssh/hermes_droplet`** (per-droplet isolation). Every `ssh`/`scp`
  command in this plan must include `-i ~/.ssh/hermes_droplet` (or use the SSH config alias in
  Task 1, Step 1b). Public key fingerprint MD5 `04:b6:ec:b5:08:7e:56:df:f2:f1:a0:ef:90:07:f4:ef`.
- Placeholders to replace with real values at runtime: `assistant.example.com` (your domain), `sk-or-...example...` (OpenRouter key), `you@example.com` (Let's Encrypt email).

---

### Task 1: Provision the Droplet and DNS

**Files:** none (DigitalOcean control panel + your domain registrar).

**Interfaces:**
- Produces: a Droplet public IPv4, an SSH login as `root`, and an A record `assistant.example.com → <IP>`.

- [x] **Step 1: Dedicated SSH key (already created)** `[local]`

The dedicated key already exists at `~/.ssh/hermes_droplet` (public key fingerprint MD5
`04:b6:ec:b5:08:7e:56:df:f2:f1:a0:ef:90:07:f4:ef`). To re-print the public key:

```bash
cat ~/.ssh/hermes_droplet.pub
```

- [ ] **Step 1b: Add an SSH config alias (after the Droplet exists)** `[local]`

So later `ssh hermes-vps` / `scp ... hermes-vps:` "just work" with the right key:

```bash
cat >> ~/.ssh/config <<'EOF'

Host hermes-vps
    HostName <DROPLET_IP>
    User hermes
    IdentityFile ~/.ssh/hermes_droplet
    IdentitiesOnly yes
EOF
```

- [ ] **Step 2: Create the Droplet** `[DigitalOcean panel]`

Create → Droplets → Ubuntu 24.04 (LTS) → Basic → Regular → **2GB / 1 vCPU ($12/mo)** → pick a region near you → **select the `hermes-droplet` SSH key** (fingerprint `04:b6:...`) → hostname `hermes`. Create.

- [ ] **Step 3: Point DNS at the Droplet** `[domain registrar]`

Add an **A record**: host `assistant` → value `<Droplet public IP>`, TTL 300.

- [ ] **Step 4: Verify SSH and DNS** `[local]`

```bash
ssh root@<DROPLET_IP> "echo connected"
dig +short assistant.example.com
```
Expected: prints `connected`; `dig` returns your Droplet IP (may take a few minutes to propagate).

- [ ] **Step 5: Commit a note of the IP/domain** `[local]`

```bash
mkdir -p infra
printf "DROPLET_IP=<IP>\nDOMAIN=assistant.example.com\n" > infra/INVENTORY.md
git add infra/INVENTORY.md && git commit -m "chore: record droplet inventory"
```
> If this dir isn't a git repo yet, run `git init` first (ask the user before initializing).

---

### Task 2: Harden the server (user, SSH, firewall, fail2ban)

**Files:** none on disk in repo; changes live on the Droplet.

**Interfaces:**
- Consumes: SSH `root` access from Task 1.
- Produces: a sudo user `hermes`, `ufw` allowing 22/80/443, `fail2ban` active, root password login disabled.

- [ ] **Step 1: Create a non-root sudo user** `[droplet]`

```bash
adduser --disabled-password --gecos "" hermes
usermod -aG sudo hermes
rsync --archive --chown=hermes:hermes ~/.ssh /home/hermes
```

- [ ] **Step 2: Install firewall + fail2ban** `[droplet]`

```bash
apt-get update && apt-get install -y ufw fail2ban
ufw default deny incoming && ufw default allow outgoing
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp
ufw --force enable
systemctl enable --now fail2ban
```

- [ ] **Step 3: Disable root password + password auth** `[droplet]`

```bash
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
```

- [ ] **Step 4: Verify hardening** `[local + droplet]`

```bash
ssh hermes@<DROPLET_IP> "sudo ufw status verbose && systemctl is-active fail2ban"
```
Expected: `ufw` shows 22/80/443 ALLOW and default deny incoming; `fail2ban` prints `active`. Login as `hermes` works.

---

### Task 3: Install Docker + Compose v2

**Files:** none in repo.

**Interfaces:**
- Consumes: `hermes` sudo user from Task 2.
- Produces: working `docker` and `docker compose` for user `hermes`.

- [ ] **Step 1: Install Docker via the official convenience script** `[droplet, as hermes]`

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker hermes
```

- [ ] **Step 2: Re-login so the docker group applies** `[local]`

```bash
ssh hermes@<DROPLET_IP> "docker version && docker compose version"
```
Expected: prints Docker Engine version and Docker Compose v2.x. No `permission denied`.

---

### Task 4: Install and join Tailscale

**Files:** none in repo.

**Interfaces:**
- Consumes: `hermes` sudo user.
- Produces: the Droplet visible in your tailnet with a `100.x.y.z` IP; private SSH path.

- [ ] **Step 1: Install Tailscale** `[droplet]`

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
```
Follow the printed URL to authenticate the Droplet into your tailnet.

- [ ] **Step 2: Verify the private route** `[local, with Tailscale running locally]`

```bash
tailscale status | grep hermes
ssh hermes@<TAILSCALE_IP> "echo tailscale-ok"
```
Expected: `hermes` host listed; SSH over the `100.x` IP prints `tailscale-ok`.

---

### Task 5: Author the IaC config files in the repo

**Files:**
- Create: `infra/docker-compose.yml`
- Create: `infra/Caddyfile`
- Create: `infra/.env.example`

**Interfaces:**
- Produces: a Compose stack defining `caddy` + `open-webui`, a `Caddyfile` proxying the domain to Open WebUI, and an `.env.example` template.

- [ ] **Step 1: Write `infra/docker-compose.yml`** `[local]`

```yaml
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    environment:
      - OPENAI_API_BASE_URL=${OPENAI_API_BASE_URL}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - DEFAULT_MODELS=${DEFAULT_MODELS}
      - WEBUI_AUTH=true
      - ENABLE_SIGNUP=${ENABLE_SIGNUP}
    volumes:
      - open-webui:/app/backend/data
    expose:
      - "8080"

  caddy:
    image: caddy:2
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - open-webui

volumes:
  open-webui:
  caddy_data:
  caddy_config:
```

- [ ] **Step 2: Write `infra/Caddyfile`** `[local]`

```
assistant.example.com {
    encode gzip
    reverse_proxy open-webui:8080
}
```
> Caddy auto-provisions and renews the Let's Encrypt cert for this domain. The email is set via the `CADDY_AGREE`/email handled on first run; alternatively add a global `{ email you@example.com }` block at the top of the file.

- [ ] **Step 3: Write `infra/.env.example`** `[local]`

```
OPENAI_API_BASE_URL=https://openrouter.ai/api/v1
OPENAI_API_KEY=sk-or-example-placeholder-replace-me
DEFAULT_MODELS=nousresearch/hermes-4-70b
ENABLE_SIGNUP=true
```

- [ ] **Step 4: Add a `.gitignore` guard for real secrets** `[local]`

```bash
printf "infra/.env\ninfra/INVENTORY.md\n" >> .gitignore
```

- [ ] **Step 5: Commit the IaC** `[local]`

```bash
git add infra/docker-compose.yml infra/Caddyfile infra/.env.example .gitignore
git commit -m "feat: add hermes assistant compose + caddy config"
```

---

### Task 6: Create OpenRouter account, key, and spend cap

**Files:** none in repo.

**Interfaces:**
- Produces: a real `sk-or-...` API key and a hard spend limit.

- [ ] **Step 1: Sign up + add credit** `[openrouter.ai]`

Create an account at openrouter.ai → add ~$5–10 of credit.

- [ ] **Step 2: Set a spend limit** `[openrouter.ai → Settings/Limits]`

Set a monthly limit (e.g. **$10**) so a runaway loop can't drain funds.

- [ ] **Step 3: Create an API key** `[openrouter.ai → Keys]`

Create a key named `hermes-droplet`; copy it (starts `sk-or-`).

- [ ] **Step 4: Verify the model is reachable** `[local]`

```bash
curl https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer sk-or-YOURKEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"nousresearch/hermes-4-70b","messages":[{"role":"user","content":"say hi"}]}'
```
Expected: HTTP 200 JSON with a `choices[0].message.content` reply from Hermes.

---

### Task 7: Deploy the stack and obtain TLS

**Files:**
- Copy to droplet: `infra/*` → `/opt/hermes/`
- Create on droplet: `/opt/hermes/.env` (real secrets, chmod 600)

**Interfaces:**
- Consumes: config from Task 5, key from Task 6, DNS from Task 1.
- Produces: a running stack serving `https://assistant.example.com`.

- [ ] **Step 1: Copy config to the Droplet** `[local]`

```bash
ssh hermes@<DROPLET_IP> "sudo mkdir -p /opt/hermes && sudo chown hermes:hermes /opt/hermes"
scp infra/docker-compose.yml infra/Caddyfile hermes@<DROPLET_IP>:/opt/hermes/
```

- [ ] **Step 2: Create the real `.env` on the Droplet** `[droplet]`

```bash
cd /opt/hermes
cat > .env <<'EOF'
OPENAI_API_BASE_URL=https://openrouter.ai/api/v1
OPENAI_API_KEY=sk-or-YOURKEY
DEFAULT_MODELS=nousresearch/hermes-4-70b
ENABLE_SIGNUP=true
EOF
chmod 600 .env
```
> Replace `assistant.example.com` in `/opt/hermes/Caddyfile` with your real domain (`sed -i 's/assistant.example.com/YOUR.DOMAIN/' Caddyfile`).

- [ ] **Step 3: Bring the stack up** `[droplet]`

```bash
cd /opt/hermes && docker compose up -d
docker compose ps
```
Expected: `caddy` and `open-webui` both `running`.

- [ ] **Step 4: Verify TLS issuance** `[local]`

```bash
sleep 30
curl -sI https://assistant.example.com | head -1
```
Expected: `HTTP/2 200` (or 302 to the login). A valid Let's Encrypt cert (no TLS warning). If it fails, check `docker compose logs caddy` for ACME errors (usually DNS not propagated).

---

### Task 8: First-run Open WebUI — admin, lock signups, select model

**Files:**
- Modify on droplet: `/opt/hermes/.env` (`ENABLE_SIGNUP=false`)

**Interfaces:**
- Consumes: running stack from Task 7.
- Produces: an admin account, signups disabled, Hermes set as default model.

- [ ] **Step 1: Create the admin account** `[browser]`

Open `https://assistant.example.com` → the **first** account you create becomes admin. Use a strong, unique password.

- [ ] **Step 2: Confirm Hermes responds** `[browser]`

Start a new chat (model `nousresearch/hermes-4-70b`) → send "Hello" → confirm a streamed reply.

- [ ] **Step 3: Disable open signups** `[droplet]`

```bash
cd /opt/hermes
sed -i 's/^ENABLE_SIGNUP=.*/ENABLE_SIGNUP=false/' .env
docker compose up -d
```

- [ ] **Step 4: Verify signups are closed** `[browser, logged out / incognito]`

Expected: the sign-up option is gone; only sign-in is available.

---

### Task 9: Backups, billing alerts, reboot resilience

**Files:** none in repo.

**Interfaces:**
- Consumes: the live deployment.
- Produces: a snapshot schedule, DO billing alert, verified auto-restart.

- [ ] **Step 1: Enable weekly snapshots** `[DigitalOcean panel]`

Droplet → Backups/Snapshots → enable weekly automated backups (or schedule manual snapshots).

- [ ] **Step 2: Set a billing alert** `[DigitalOcean → Billing → Alerts]`

Add alerts at **$50** and **$90** of usage against the $113 credit.

- [ ] **Step 3: Verify reboot resilience** `[droplet]`

```bash
sudo reboot
# wait ~30s, then from local:
ssh hermes@<DROPLET_IP> "cd /opt/hermes && docker compose ps"
```
Expected: both containers back to `running` automatically (thanks to `restart: unless-stopped`).

- [ ] **Step 4: Final end-to-end verification** `[local + browser]`

```bash
curl -sI https://assistant.example.com | head -1   # HTTP/2 200|302, valid cert
```
Plus: log in, send a Hermes chat, get a reply. Confirm `nmap <DROPLET_IP>` shows only 22/80/443 open.

---

## Self-Review (against the spec)

- **Spec §2 (API-backed model):** Tasks 5–8 wire `nousresearch/hermes-4-70b` via OpenRouter. ✓
- **Spec §3–4 (architecture/components):** Tasks 1,3,5,7 build Droplet + Docker + Caddy + Open WebUI. ✓
- **Spec §5–6 (data flow/config):** Task 5 `.env.example`, Task 7 real `.env`. ✓
- **Spec §7 (security):** Task 2 (ufw/fail2ban/SSH), Task 4 (Tailscale), Task 8 (admin + signups off), Task 6 (spend cap). ✓
- **Spec §8 (backup/cost):** Task 9 snapshots + billing alerts + OpenRouter cap. ✓
- **Spec §9 (verification):** Verification steps in Tasks 7,8,9 cover all six DoD checks + Tailscale. ✓
- **Placeholder scan:** all `example.com`/`sk-or-example` values are explicitly flagged as runtime replacements per Global Constraints. ✓
- **Type/name consistency:** env var names (`OPENAI_API_BASE_URL`, `DEFAULT_MODELS`, `ENABLE_SIGNUP`) and service names (`open-webui`, `caddy`) are identical across compose, Caddyfile, and tasks. ✓
