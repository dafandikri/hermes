#!/usr/bin/env bash
# Switch the public web app at $DOMAIN from Open WebUI to the Hermes dashboard, which runs on
# the Codex subscription (no API key, no separate admin account). Idempotent.
#
# The dashboard binds loopback and trusts local connections, so exposure is gated by Caddy
# basic-auth at the edge. Order matters (no-OOM): swap -> free RAM -> pre-build -> service ->
# render Caddyfile -> apply -> verify the gate blocks.
#
# Usage: scripts/switch-to-dashboard.sh [ssh-host]    (default: hermes-vps)
#   DASH_USER  web username (default: admin)
#   DASH_PASS  web password (default: generated and printed once)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"
REMOTE_DIR="/opt/hermes"
DASH_USER="${DASH_USER:-admin}"
require_cmd ssh
require_cmd scp

if [ -n "${DASH_PASS:-}" ]; then
  dash_pass="$DASH_PASS"
  generated=0
else
  # openssl avoids the `tr | head` SIGPIPE-under-pipefail trap (no pipe at all).
  dash_pass="$(openssl rand -hex 16)"
  generated=1
fi

# 1. swap safety net
./scripts/ensure-swap.sh "$HOST"

# 1b. model/auth invariant — the dashboard is useless if provider/model drift.
./scripts/configure-model.sh "$HOST"

# 2. free RAM — stop Open WebUI (kept defined; the dashboard replaces it as the web face)
info "Stopping Open WebUI to free memory (container kept, not removed)"
ssh "$HOST" "cd ${REMOTE_DIR} && sudo docker compose stop open-webui > /dev/null 2>&1 || true"

# 3. pre-build the dashboard once, then confirm it serves on loopback
info "Pre-building the dashboard web UI (one-time, memory-heavy; swap covers it)"
ssh_host "$HOST" 'nohup hermes dashboard --host 127.0.0.1 --port 9119 --no-open > /tmp/dash-build.log 2>&1 & echo $! > /tmp/dash.pid'
ssh "$HOST" '
  served=0
  for _ in $(seq 1 72); do
    if curl -sS -o /dev/null http://127.0.0.1:9119/ 2> /dev/null; then served=1; break; fi
    sleep 10
  done
  [ -f /tmp/dash.pid ] && kill "$(cat /tmp/dash.pid)" 2> /dev/null || true
  if [ "$served" = 1 ]; then
    echo "  dashboard built and served OK"
  else
    echo "  dashboard did not serve in time:"; tail -20 /tmp/dash-build.log; exit 1
  fi
' || die "dashboard build/serve failed"

# 4. install + start the systemd user service (reuses the built dist via --skip-build)
info "Installing the dashboard systemd service"
scp -q infra/hermes-dashboard.service "$HOST:/tmp/hermes-dashboard.service"
ssh_host "$HOST" '
  mkdir -p ~/.config/systemd/user
  mv /tmp/hermes-dashboard.service ~/.config/systemd/user/hermes-dashboard.service
  systemctl --user daemon-reload
  systemctl --user enable --now hermes-dashboard.service
  sleep 6
  systemctl --user is-active hermes-dashboard.service
' || die "dashboard service failed to start"

# 5. hash the password (bcrypt via caddy), render the Caddyfile, install it on the droplet
info "Hashing the web password (bcrypt)"
dash_hash="$(ssh "$HOST" "sudo docker run --rm caddy:2 caddy hash-password --plaintext $(printf '%q' "$dash_pass")" 2> /dev/null | tr -d '\r\n')"
[ -n "$dash_hash" ] || die "failed to hash password"

info "Rendering and installing the dashboard Caddyfile (secrets stay on the droplet)"
template="$(cat infra/Caddyfile.dashboard)"
rendered="${template//__DASH_USER__/$DASH_USER}"
rendered="${rendered//__DASH_HASH__/$dash_hash}"
printf '%s\n' "$rendered" | ssh "$HOST" "cat > ${REMOTE_DIR}/Caddyfile"
ssh "$HOST" "sudo docker run --rm -v ${REMOTE_DIR}/Caddyfile:/etc/caddy/Caddyfile caddy:2 caddy fmt --overwrite /etc/caddy/Caddyfile >/dev/null"

# 6. apply: copy compose and force-recreate Caddy. Caddyfile is a file bind mount; if an
#    operator edits it with inode-replacing tools (`sed -i`, temp+mv), reload can keep seeing
#    the old mounted inode. Recreate guarantees the container sees the current file path.
info "Applying new Caddy config (force-recreate for file bind mount correctness)"
scp -q infra/docker-compose.yml "$HOST:${REMOTE_DIR}/"
ssh "$HOST" "cd ${REMOTE_DIR} && sudo docker compose up -d --force-recreate caddy"

# 7. verify the edge gate: no creds -> 401, with creds -> not 401
domain="$(ssh "$HOST" "grep ^DOMAIN ${REMOTE_DIR}/.env | cut -d= -f2")"
sleep 6
no_auth="$(curl -s -o /dev/null -w '%{http_code}' "https://${domain}/" || true)"
with_auth="$(curl -s -u "${DASH_USER}:${dash_pass}" -o /dev/null -w '%{http_code}' "https://${domain}/" || true)"
info "Gate check — no-auth=${no_auth} (want 401), with-auth=${with_auth} (want not 401)"
[ "$no_auth" = 401 ] && ok "edge gate blocks unauthenticated access" || warn "expected 401 without creds, got ${no_auth}"
[ "$with_auth" != 401 ] && ok "edge gate opens with credentials (status ${with_auth})" || warn "auth rejected valid credentials"

if [[ "$with_auth" == 200 ]]; then
  DASH_USER="$DASH_USER" DASH_PASS="$dash_pass" ./scripts/verify-runtime.sh "$HOST"
else
  ./scripts/verify-runtime.sh "$HOST" --skip-web
fi

ok "dashboard is now the web app at https://${domain}"
if [ "$generated" = 1 ]; then
  printf '\n  +-- WEB LOGIN (save now — shown once) -----------------\n'
  printf '  |  URL:      https://%s\n' "$domain"
  printf '  |  Username: %s\n' "$DASH_USER"
  printf '  |  Password: %s\n' "$dash_pass"
  printf '  +-----------------------------------------------------\n'
fi
