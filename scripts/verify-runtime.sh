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

info "Verifying Hermes runtime invariants on $HOST"

remote_reader='from pathlib import Path
import re

text = (Path.home() / ".hermes" / "config.yaml").read_text()

def val(key: str) -> str:
    match = re.search(rf"^  {key}:\s*(.*)$", text, re.MULTILINE)
    return (match.group(1).strip().strip("\"'"'"'") if match else "")

print(val("provider"))
print(val("default"))'
remote_reader_b64="$(printf '%s' "$remote_reader" | base64 | tr -d '\n')"
state_output="$(ssh "$HOST" "printf '%s' '$remote_reader_b64' | base64 --decode | python3")"
provider="$(printf '%s\n' "$state_output" | sed -n '1p')"
model="$(printf '%s\n' "$state_output" | sed -n '2p')"

[[ "$provider" == "$EXPECTED_PROVIDER" ]] || die "provider mismatch: got '$provider', want '$EXPECTED_PROVIDER'"
[[ -n "$model" ]] || die "Hermes model is blank; set HERMES_MODEL and run scripts/configure-model.sh"
[[ "$model" == "$EXPECTED_MODEL" ]] || die "model mismatch: got '$model', want '$EXPECTED_MODEL'"
ok "model/provider invariant holds (${provider} / ${model})"

auth_status="$(ssh_host "$HOST" 'hermes auth status openai-codex 2>&1 | head -1')"
[[ "$auth_status" == *"logged in"* ]] || die "openai-codex auth is not logged in: ${auth_status}"
ok "openai-codex auth is logged in"

dashboard_state="$(ssh_host "$HOST" 'systemctl --user is-active hermes-dashboard.service 2>/dev/null || true')"
[[ "$dashboard_state" == "active" ]] || die "hermes-dashboard.service is not active (${dashboard_state:-missing})"
ok "dashboard service active"

gateway_state="$(ssh_host "$HOST" 'systemctl --user is-active hermes-gateway.service 2>/dev/null || true')"
[[ "$gateway_state" == "active" ]] || die "hermes-gateway.service is not active (${gateway_state:-missing})"
ok "gateway service active"

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
  else
    warn "DASH_USER/DASH_PASS not set; skipped authenticated 200 check"
  fi
fi

ok "runtime verification passed"
