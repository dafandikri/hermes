#!/usr/bin/env bash
# Idempotently install and enable RTK (Rust Token Killer) for Hermes terminal output filtering.
# RTK is a non-secret runtime optimization: it rewrites/summarizes noisy terminal commands before
# their output reaches the LLM context. Critical debugging should still bypass RTK for raw logs.
#
# Usage:
#   RTK_HERMES_MODE=rewrite scripts/configure-rtk.sh [ssh-host]
#   scripts/configure-rtk.sh [ssh-host] --skip-verify
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"
SKIP_VERIFY="${2:-}"
RTK_HERMES_MODE="${RTK_HERMES_MODE:-rewrite}"
RTK_HERMES_TIMEOUT_MS="${RTK_HERMES_TIMEOUT_MS:-2000}"
RTK_HERMES_PREVIEW_MARKER="${RTK_HERMES_PREVIEW_MARKER:-true}"
RTK_HERMES_BACKENDS="${RTK_HERMES_BACKENDS:-local}"

[[ "$RTK_HERMES_MODE" =~ ^(rewrite|suggest|off)$ ]] || die "RTK_HERMES_MODE must be rewrite, suggest, or off"
[[ "$RTK_HERMES_TIMEOUT_MS" =~ ^[0-9]+$ ]] || die "RTK_HERMES_TIMEOUT_MS must be an integer"
[[ "$RTK_HERMES_PREVIEW_MARKER" =~ ^(true|false)$ ]] || die "RTK_HERMES_PREVIEW_MARKER must be true or false"
[[ "$RTK_HERMES_BACKENDS" =~ ^[A-Za-z0-9_.:,/-]+$ ]] || die "RTK_HERMES_BACKENDS must contain only backend names, commas, colons, dots, underscores, slashes, or dashes"

info "Configuring RTK terminal filtering on $HOST"

remote_script='set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

if ! command -v rtk >/dev/null 2>&1; then
  installer="$(mktemp)"
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh -o "$installer"
  sh "$installer"
  rm -f "$installer"
fi

if ! hermes plugins list --plain --no-bundled 2>/dev/null | grep -q "rtk-rewrite"; then
  hermes plugins install seamusmore/rtk-rewrite >/dev/null
fi
hermes plugins enable rtk-rewrite >/dev/null

env_file="$HOME/.hermes/.env"
touch "$env_file"
chmod 600 "$env_file"
upsert_env() {
  key="$1"
  value="$2"
  if grep -qE "^#? *${key}=" "$env_file"; then
    sed -i -E "s|^#? *${key}=.*|${key}=${value}|" "$env_file"
  else
    printf "%s=%s\n" "$key" "$value" >> "$env_file"
  fi
}

upsert_env RTK_HERMES_MODE "__RTK_HERMES_MODE__"
upsert_env RTK_HERMES_TIMEOUT_MS "__RTK_HERMES_TIMEOUT_MS__"
upsert_env RTK_HERMES_PREVIEW_MARKER "__RTK_HERMES_PREVIEW_MARKER__"
upsert_env RTK_HERMES_BACKENDS "__RTK_HERMES_BACKENDS__"

if systemctl --user is-active --quiet hermes-gateway.service 2>/dev/null; then
  systemctl --user restart hermes-gateway.service
fi
if systemctl --user is-active --quiet hermes-dashboard.service 2>/dev/null; then
  systemctl --user restart hermes-dashboard.service
fi

rtk --version
hermes plugins list --plain --no-bundled | grep "rtk-rewrite"
'
remote_script="${remote_script//__RTK_HERMES_MODE__/$RTK_HERMES_MODE}"
remote_script="${remote_script//__RTK_HERMES_TIMEOUT_MS__/$RTK_HERMES_TIMEOUT_MS}"
remote_script="${remote_script//__RTK_HERMES_PREVIEW_MARKER__/$RTK_HERMES_PREVIEW_MARKER}"
remote_script="${remote_script//__RTK_HERMES_BACKENDS__/$RTK_HERMES_BACKENDS}"
remote_script_b64="$(printf '%s' "$remote_script" | base64 | tr -d '\n')"
if [[ "$HOST" =~ ^(local|localhost|127\.0\.0\.1|self)$ ]]; then
  printf '%s' "$remote_script_b64" | base64 --decode | bash
else
  ssh_host "$HOST" "printf '%s' '$remote_script_b64' | base64 --decode | bash"
fi

if [[ "$SKIP_VERIFY" != "--skip-verify" ]]; then
  ./scripts/verify-runtime.sh "$HOST" --skip-web
fi

ok "RTK terminal filtering configured"
