#!/usr/bin/env bash
# Verify configured Hermes messaging channels without printing credentials.
# Unconfigured optional channels are reported as skipped.
#
# Usage: scripts/verify-channels.sh [ssh-host]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"

info "Verifying Hermes messaging channels on $HOST"

ssh_host "$HOST" "python3 - <<'PY'
from pathlib import Path
import re
import sys

env_path = Path.home() / '.hermes' / '.env'
config_path = Path.home() / '.hermes' / 'config.yaml'

values = {}
for raw in env_path.read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    key, value = line.split('=', 1)
    values[key.strip()] = value.strip()

errors = []

def require_keys(platform, enabled, required):
    if not enabled:
        print(f'  {platform}: not configured')
        return
    missing = [key for key in required if not values.get(key)]
    if missing:
        errors.append(f'{platform}: missing ' + ', '.join(missing))
    else:
        print(f'  {platform}: credentials and allowlist configured')

require_keys(
    'Telegram',
    bool(values.get('TELEGRAM_BOT_TOKEN')),
    ['TELEGRAM_BOT_TOKEN', 'TELEGRAM_ALLOWED_USERS'],
)
require_keys(
    'Discord',
    bool(values.get('DISCORD_BOT_TOKEN')),
    ['DISCORD_BOT_TOKEN', 'DISCORD_ALLOWED_USERS'],
)

line_enabled = bool(values.get('LINE_CHANNEL_ACCESS_TOKEN') or values.get('LINE_CHANNEL_SECRET'))
line_allowlisted = any(values.get(key) for key in (
    'LINE_ALLOWED_USERS',
    'LINE_ALLOWED_GROUPS',
    'LINE_ALLOWED_ROOMS',
))
require_keys(
    'LINE',
    line_enabled,
    ['LINE_CHANNEL_ACCESS_TOKEN', 'LINE_CHANNEL_SECRET', 'LINE_PUBLIC_URL'],
)
if line_enabled and not line_allowlisted:
    errors.append('LINE: no user/group/room allowlist')
if line_enabled:
    config = config_path.read_text()
    if not re.search(r'(?ms)^gateway:.*?^  platforms:.*?^    line:.*?^      enabled:\\s*true\\s*$', config):
        errors.append('LINE: gateway.platforms.line.enabled is not true')

whatsapp_enabled = values.get('WHATSAPP_ENABLED', '').lower() == 'true'
require_keys(
    'WhatsApp',
    whatsapp_enabled,
    ['WHATSAPP_ENABLED', 'WHATSAPP_MODE', 'WHATSAPP_ALLOWED_USERS'],
)
if whatsapp_enabled:
    session = Path.home() / '.hermes' / 'whatsapp' / 'session'
    if not session.is_dir() or not any(session.iterdir()):
        errors.append('WhatsApp: pairing session is missing; run make pair-whatsapp')
    else:
        print('  WhatsApp: pairing session present')

if errors:
    for error in errors:
        print(f'ERROR: {error}', file=sys.stderr)
    raise SystemExit(1)
PY
"

gateway_state="$(ssh_host "$HOST" 'systemctl --user is-active hermes-gateway.service 2>/dev/null || true')"
[[ "$gateway_state" == "active" ]] || die "hermes-gateway.service is not active (${gateway_state:-missing})"

line_configured="$(ssh_host "$HOST" 'grep -q "^LINE_CHANNEL_ACCESS_TOKEN=." ~/.hermes/.env 2>/dev/null && echo yes || true')"
if [[ "$line_configured" == "yes" ]]; then
  line_health=""
  for _ in $(seq 1 30); do
    line_health="$(ssh_host "$HOST" 'curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:8646/line/webhook/health 2>/dev/null || true')"
    [[ "$line_health" == "200" ]] && break
    sleep 2
  done
  [[ "$line_health" == "200" ]] ||
    die "LINE adapter health returned ${line_health:-no response}, want 200; inspect ~/.hermes/logs/gateway.log"
  ok "LINE adapter health passes"
fi

whatsapp_configured="$(ssh_host "$HOST" 'grep -q "^WHATSAPP_ENABLED=true" ~/.hermes/.env 2>/dev/null && echo yes || true')"
if [[ "$whatsapp_configured" == "yes" ]]; then
  whatsapp_bridge="$(ssh_host "$HOST" 'pgrep -f "scripts/whatsapp-bridge/bridge.js" >/dev/null && echo active || true')"
  [[ "$whatsapp_bridge" == "active" ]] || die "WhatsApp bridge process is not active"
  ok "WhatsApp bridge process active"
fi

ok "messaging channel verification passed"
