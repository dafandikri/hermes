#!/usr/bin/env bash
# Idempotently deploy/refresh the Caddy + Open WebUI stack on the droplet.
# Usage: scripts/deploy-webapp.sh [ssh-host]   (default host: hermes-vps)
# The real secrets live only in /opt/hermes/.env on the droplet (chmod 600) — never here.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"
REMOTE_DIR="/opt/hermes"

require_cmd ssh
require_cmd scp

info "Ensuring $REMOTE_DIR exists on $HOST"
ssh "$HOST" "sudo mkdir -p $REMOTE_DIR && sudo chown \$(whoami): $REMOTE_DIR"

info "Copying compose + Caddyfile (config as code)"
scp -q infra/docker-compose.yml infra/Caddyfile "$HOST:$REMOTE_DIR/"

info "Checking remote .env exists"
if ! ssh "$HOST" "test -f $REMOTE_DIR/.env"; then
  warn "no $REMOTE_DIR/.env on host — copy infra/.env.example there and fill it in first"
  die "aborting: refusing to deploy without an .env"
fi

info "Starting stack (idempotent)"
ssh "$HOST" "cd $REMOTE_DIR && sudo docker compose up -d"

info "Waiting for open-webui health"
ssh "$HOST" '
  for i in $(seq 1 18); do
    h=$(sudo docker inspect --format "{{.State.Health.Status}}" open-webui 2>/dev/null || echo none)
    [ "$h" = healthy ] && { echo "healthy"; exit 0; }
    sleep 5
  done
  echo "did not reach healthy in time"; exit 1
' || die "open-webui did not become healthy"

domain="$(ssh "$HOST" "grep ^DOMAIN $REMOTE_DIR/.env | cut -d= -f2")"
info "Verifying HTTPS for ${domain:-<unset>}"
code="$(ssh "$HOST" "curl -sS -o /dev/null -w '%{http_code}' https://${domain}/ || true")"
[[ "$code" == "200" || "$code" == "302" ]] && ok "https://${domain} -> $code" || warn "unexpected status: $code"

ok "webapp deploy complete"
