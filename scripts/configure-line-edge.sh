#!/usr/bin/env bash
# Expose only Hermes's signed LINE webhook/media route through the existing Caddy
# site. The dashboard remains protected by basic-auth.
#
# Usage: scripts/configure-line-edge.sh [ssh-host]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"
REMOTE_DIR="/opt/hermes"

info "Installing the LINE webhook route on $HOST"
ssh_host "$HOST" "python3 - <<'PY'
from pathlib import Path

path = Path('${REMOTE_DIR}/Caddyfile')
text = path.read_text()

if 'reverse_proxy /line/* 127.0.0.1:8646' not in text:
    marker = 'basic_auth {'
    if marker not in text:
        raise SystemExit('dashboard basic_auth block not found')
    text = text.replace(
        marker,
        '@dashboard not path /line/*\\n\\tbasic_auth @dashboard {',
        1,
    )
    dashboard_proxy = 'reverse_proxy 127.0.0.1:9119'
    text = text.replace(
        dashboard_proxy,
        'reverse_proxy /line/* 127.0.0.1:8646\\n\\n\\t' + dashboard_proxy,
        1,
    )
    path.write_text(text)

print('  LINE edge route present')
PY
cd ${REMOTE_DIR}
sudo docker run --rm -v ${REMOTE_DIR}/Caddyfile:/etc/caddy/Caddyfile:ro \
  caddy:2 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
sudo docker compose up -d --force-recreate caddy >/dev/null
"

domain="$(ssh_host "$HOST" "grep '^DOMAIN=' ${REMOTE_DIR}/.env | cut -d= -f2")"
[[ -n "$domain" ]] || die "DOMAIN is missing from ${REMOTE_DIR}/.env"

code="$(curl -sS -o /dev/null -w '%{http_code}' "https://${domain}/line/webhook/health" || true)"
[[ "$code" != "401" ]] || die "LINE route is still blocked by dashboard basic-auth"
ok "LINE edge route is public (health status ${code}; adapter may not be running until credentials are configured)"
