#!/usr/bin/env bash
# Fail-fast runtime guard for the live Hermes droplet. This catches "looks deployed but
# cannot answer" errors such as openai-codex with a blank model, expired auth, broken
# gateway, or a dashboard edge gate that no longer blocks unauthenticated traffic.
#
# Usage:
#   DASH_USER=admin DASH_PASS=... scripts/verify-runtime.sh [ssh-host]
#   scripts/verify-runtime.sh [ssh-host] --skip-web
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"
SKIP_WEB="${2:-}"
EXPECTED_PROVIDER="${HERMES_PROVIDER:-openai-codex}"
EXPECTED_MODEL="${HERMES_MODEL:-openai/gpt-5.5}"
EXPECTED_COMPRESSION_ENABLED="${HERMES_COMPRESSION_ENABLED:-true}"
EXPECTED_AUTORAISE="${HERMES_CODEX_GPT55_AUTORAISE:-false}"
EXPECTED_RTK_MODE="${RTK_HERMES_MODE:-rewrite}"
EXPECTED_RTK_BACKENDS="${RTK_HERMES_BACKENDS:-local}"

info "Verifying Hermes runtime invariants on $HOST"

remote_reader='from pathlib import Path
import re

text = (Path.home() / ".hermes" / "config.yaml").read_text()

def val(key: str) -> str:
    match = re.search(rf"^  {key}:\s*(.*)$", text, re.MULTILINE)
    return (match.group(1).strip().strip("\"'"'"'") if match else "")

print(val("provider"))
print(val("default"))

compression = re.search(r"^compression:\n(?P<body>(?:  .*\n?)*)", text, re.MULTILINE)
body = compression.group("body") if compression else ""
match = re.search(r"^  codex_gpt55_autoraise:\s*(.*)$", body, re.MULTILINE)
enabled = re.search(r"^  enabled:\s*(.*)$", body, re.MULTILINE)
print((enabled.group(1).strip().strip("\"'"'"'") if enabled else ""))
print((match.group(1).strip().strip("\"'"'"'") if match else ""))'
remote_reader_b64="$(printf '%s' "$remote_reader" | base64 | tr -d '\n')"
state_output="$(ssh_host "$HOST" "printf '%s' '$remote_reader_b64' | base64 --decode | python3")"
provider="$(printf '%s\n' "$state_output" | sed -n '1p')"
model="$(printf '%s\n' "$state_output" | sed -n '2p')"
compression_enabled="$(printf '%s\n' "$state_output" | sed -n '3p')"
autoraise="$(printf '%s\n' "$state_output" | sed -n '4p')"

[[ "$provider" == "$EXPECTED_PROVIDER" ]] || die "provider mismatch: got '$provider', want '$EXPECTED_PROVIDER'"
[[ -n "$model" ]] || die "Hermes model is blank; set HERMES_MODEL and run scripts/configure-model.sh"
[[ "$model" == "$EXPECTED_MODEL" ]] || die "model mismatch: got '$model', want '$EXPECTED_MODEL'"
ok "model/provider invariant holds (${provider} / ${model})"
[[ "$compression_enabled" == "$EXPECTED_COMPRESSION_ENABLED" ]] || die "compression.enabled mismatch: got '$compression_enabled', want '$EXPECTED_COMPRESSION_ENABLED'"
ok "auto-compression stays enabled (${compression_enabled})"
[[ "$autoraise" == "$EXPECTED_AUTORAISE" ]] || die "compression.codex_gpt55_autoraise mismatch: got '$autoraise', want '$EXPECTED_AUTORAISE'"
ok "Codex GPT-5.5 auto-raise notice stays suppressed (${autoraise})"

rtk_state="$(ssh_host "$HOST" 'export PATH=$HOME/.local/bin:$PATH; rtk --version 2>/dev/null || true')"
[[ "$rtk_state" == rtk\ * ]] || die "RTK binary is missing or not executable: ${rtk_state:-missing}"
ok "RTK binary available (${rtk_state})"

rtk_plugin="$(ssh_host "$HOST" 'hermes plugins list --plain --no-bundled 2>/dev/null | grep -E "rtk-rewrite" | head -1 || true')"
[[ "$rtk_plugin" == enabled*rtk-rewrite* ]] || die "rtk-rewrite plugin is not enabled: ${rtk_plugin:-missing}"
ok "RTK Hermes plugin enabled"

rtk_env="$(ssh_host "$HOST" 'grep -E "^RTK_HERMES_(MODE|BACKENDS)=" ~/.hermes/.env 2>/dev/null || true')"
[[ "$rtk_env" == *"RTK_HERMES_MODE=${EXPECTED_RTK_MODE}"* ]] || die "RTK_HERMES_MODE mismatch; want ${EXPECTED_RTK_MODE}"
[[ "$rtk_env" == *"RTK_HERMES_BACKENDS=${EXPECTED_RTK_BACKENDS}"* ]] || die "RTK_HERMES_BACKENDS mismatch; want ${EXPECTED_RTK_BACKENDS}"
ok "RTK env defaults hold (${EXPECTED_RTK_MODE} / ${EXPECTED_RTK_BACKENDS})"

auth_status="$(ssh_host "$HOST" 'hermes auth status openai-codex 2>&1 | head -1')"
[[ "$auth_status" == *"logged in"* ]] || die "openai-codex auth is not logged in: ${auth_status}"
ok "openai-codex auth is logged in"

dashboard_state="$(ssh_host "$HOST" '
  for _ in $(seq 1 45); do
    state="$(systemctl --user is-active hermes-dashboard.service 2>/dev/null || true)"
    if [ "$state" = active ]; then
      sleep 2
      systemctl --user is-active hermes-dashboard.service 2>/dev/null || true
      exit 0
    fi
    sleep 2
  done
  systemctl --user is-active hermes-dashboard.service 2>/dev/null || true
')"
[[ "$dashboard_state" == "active" ]] || die "hermes-dashboard.service is not active (${dashboard_state:-missing})"
ok "dashboard service active"

gateway_state="$(ssh_host "$HOST" '
  for _ in $(seq 1 45); do
    state="$(systemctl --user is-active hermes-gateway.service 2>/dev/null || true)"
    if [ "$state" = active ]; then
      sleep 2
      systemctl --user is-active hermes-gateway.service 2>/dev/null || true
      exit 0
    fi
    sleep 2
  done
  systemctl --user is-active hermes-gateway.service 2>/dev/null || true
')"
[[ "$gateway_state" == "active" ]] || die "hermes-gateway.service is not active (${gateway_state:-missing})"
ok "gateway service active"

./scripts/verify-channels.sh "$HOST"

if [[ "$SKIP_WEB" != "--skip-web" ]]; then
  domain="$(ssh_host "$HOST" 'grep ^DOMAIN /opt/hermes/.env 2>/dev/null | cut -d= -f2')"
  [[ -n "$domain" ]] || die "DOMAIN missing from /opt/hermes/.env"

  no_auth="$(curl -sS -o /dev/null -w '%{http_code}' "https://${domain}/" || true)"
  [[ "$no_auth" == "401" ]] || die "web edge auth invariant failed: no-auth got ${no_auth}, want 401"
  ok "web edge blocks unauthenticated access"

  if [[ -n "${DASH_USER:-}" && -n "${DASH_PASS:-}" ]]; then
    with_auth="$(curl -sS -u "${DASH_USER}:${DASH_PASS}" -o /dev/null -w '%{http_code}' "https://${domain}/" || true)"
    [[ "$with_auth" == "200" ]] || die "web dashboard auth check failed: got ${with_auth}, want 200"
    ok "web dashboard opens with supplied credentials"

    ws_status="$(
      DASH_DOMAIN="$domain" DASH_USER="$DASH_USER" DASH_PASS="$DASH_PASS" python3 - << 'PY'
import base64
import os
import re
import socket
import ssl
import sys
import urllib.request

domain = os.environ["DASH_DOMAIN"]
user = os.environ["DASH_USER"]
password = os.environ["DASH_PASS"]
creds = base64.b64encode(f"{user}:{password}".encode()).decode()

req = urllib.request.Request(
    f"https://{domain}/",
    headers={"Authorization": f"Basic {creds}"},
)
html = urllib.request.urlopen(req, timeout=15).read().decode()
match = re.search(r'__HERMES_SESSION_TOKEN__="([^"]+)"', html)
if not match:
    print("no-session-token")
    sys.exit(1)

token = match.group(1)
key = base64.b64encode(os.urandom(16)).decode()
request = (
    f"GET /api/pty?token={token}&channel=runtime-check HTTP/1.1\r\n"
    f"Host: {domain}\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    "Sec-WebSocket-Version: 13\r\n"
    f"Origin: https://{domain}\r\n"
    f"Authorization: Basic {creds}\r\n"
    "\r\n"
).encode()

ctx = ssl.create_default_context()
with socket.create_connection((domain, 443), timeout=15) as sock:
    with ctx.wrap_socket(sock, server_hostname=domain) as tls:
        tls.sendall(request)
        response = tls.recv(4096).decode("latin1", errors="replace")

status = response.split("\r\n", 1)[0]
print(status)
if " 101 " not in status:
    sys.exit(1)
PY
    )" || die "dashboard WebSocket/PTY check failed: ${ws_status:-no response}"
    ok "dashboard WebSocket/PTY opens (${ws_status})"
  else
    warn "DASH_USER/DASH_PASS not set; skipped authenticated 200 check"
  fi
fi

ok "runtime verification passed"
