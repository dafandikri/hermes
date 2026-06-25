#!/usr/bin/env bash
# Read-only health check of both tracks on the droplet.
# Usage: scripts/status.sh [ssh-host]   (default: hermes-vps)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"

info "Web app (Caddy + Open WebUI)"
ssh_host "$HOST" 'cd /opt/hermes && sudo docker compose ps --format "  {{.Service}}: {{.Status}}" 2>/dev/null || echo "  (stack not found)"'
domain="$(ssh_host "$HOST" 'grep ^DOMAIN /opt/hermes/.env 2>/dev/null | cut -d= -f2' || true)"
if [[ -n "${domain}" ]]; then
  code="$(ssh_host "$HOST" "curl -sS -o /dev/null -w '%{http_code}' https://${domain}/ || true")"
  ok "https://${domain} -> ${code}"
fi

info "Hermes Agent"
ssh_host "$HOST" '
  echo "  version: $(hermes --version 2>&1 | head -1)"
  echo "  model: $(grep -E "^  default:" ~/.hermes/config.yaml | tr -s " ")"
  echo "  provider: $(grep -E "^  provider:" ~/.hermes/config.yaml | tr -s " ")"
  echo "  auth(openai-codex): $(hermes auth status openai-codex 2>&1 | head -1)"
  echo "  rtk: $(rtk --version 2>/dev/null || echo missing)"
  echo "  rtk plugin: $(hermes plugins list --plain --no-bundled 2>/dev/null | grep -E "rtk-rewrite" | head -1 || echo missing)"
  echo "  gateway: $(hermes gateway status 2>&1 | head -1)"
  echo "  LINE: $(grep -q "^LINE_CHANNEL_ACCESS_TOKEN=." ~/.hermes/.env 2>/dev/null && echo configured || echo not-configured)"
  echo "  WhatsApp: $([ -d ~/.hermes/whatsapp/session ] && echo paired || echo not-paired)"
'

./scripts/verify-runtime.sh "$HOST" --skip-web

ok "status check complete"
