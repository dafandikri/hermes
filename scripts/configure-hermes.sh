#!/usr/bin/env bash
# Configure the Hermes Agent messaging gateway (Telegram, Discord, and/or LINE)
# idempotently,
# then install + start it as a service. Secrets are read from the ENVIRONMENT and piped
# over stdin (never passed as argv, so they don't leak into the remote process list).
#
# Usage:
#   export TELEGRAM_BOT_TOKEN=... TELEGRAM_ALLOWED_USERS=123
#   export DISCORD_BOT_TOKEN=...  DISCORD_ALLOWED_USERS=456   # optional
#   export LINE_CHANNEL_ACCESS_TOKEN=... LINE_CHANNEL_SECRET=...
#   export LINE_ALLOWED_USERS=U... LINE_PUBLIC_URL=https://assistant.example.com
#   scripts/configure-hermes.sh [ssh-host]                    # default: hermes-vps
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"

./scripts/configure-model.sh "$HOST"

# Collect whichever platform secrets are present in the environment.
declare -a pairs=()
[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && pairs+=("TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}")
[[ -n "${TELEGRAM_ALLOWED_USERS:-}" ]] && pairs+=("TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}")
[[ -n "${DISCORD_BOT_TOKEN:-}" ]] && pairs+=("DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}")
[[ -n "${DISCORD_ALLOWED_USERS:-}" ]] && pairs+=("DISCORD_ALLOWED_USERS=${DISCORD_ALLOWED_USERS}")
[[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" ]] && pairs+=("LINE_CHANNEL_ACCESS_TOKEN=${LINE_CHANNEL_ACCESS_TOKEN}")
[[ -n "${LINE_CHANNEL_SECRET:-}" ]] && pairs+=("LINE_CHANNEL_SECRET=${LINE_CHANNEL_SECRET}")
[[ -n "${LINE_ALLOWED_USERS:-}" ]] && pairs+=("LINE_ALLOWED_USERS=${LINE_ALLOWED_USERS}")
[[ -n "${LINE_ALLOWED_GROUPS:-}" ]] && pairs+=("LINE_ALLOWED_GROUPS=${LINE_ALLOWED_GROUPS}")
[[ -n "${LINE_ALLOWED_ROOMS:-}" ]] && pairs+=("LINE_ALLOWED_ROOMS=${LINE_ALLOWED_ROOMS}")
[[ -n "${LINE_PUBLIC_URL:-}" ]] && pairs+=("LINE_PUBLIC_URL=${LINE_PUBLIC_URL}")
[[ -n "${LINE_HOME_CHANNEL:-}" ]] && pairs+=("LINE_HOME_CHANNEL=${LINE_HOME_CHANNEL}")

[[ ${#pairs[@]} -gt 0 ]] ||
  die "no platform settings in environment (set Telegram, Discord, and/or LINE variables)"

if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -z "${TELEGRAM_ALLOWED_USERS:-}" ]]; then
  die "TELEGRAM_BOT_TOKEN requires TELEGRAM_ALLOWED_USERS"
fi
if [[ -n "${DISCORD_BOT_TOKEN:-}" && -z "${DISCORD_ALLOWED_USERS:-}" ]]; then
  die "DISCORD_BOT_TOKEN requires DISCORD_ALLOWED_USERS"
fi
if [[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" || -n "${LINE_CHANNEL_SECRET:-}" ]]; then
  [[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" && -n "${LINE_CHANNEL_SECRET:-}" ]] ||
    die "LINE requires both LINE_CHANNEL_ACCESS_TOKEN and LINE_CHANNEL_SECRET"
  [[ -n "${LINE_ALLOWED_USERS:-}${LINE_ALLOWED_GROUPS:-}${LINE_ALLOWED_ROOMS:-}" ]] ||
    die "LINE requires at least one LINE_ALLOWED_USERS/GROUPS/ROOMS allowlist"
  [[ -n "${LINE_PUBLIC_URL:-}" ]] || die "LINE requires LINE_PUBLIC_URL for the public webhook/media base URL"
fi
info "Writing ${#pairs[@]} key(s) to ~/.hermes/.env on $HOST (secrets via stdin, not argv)"
# Remote upsert script: reads KEY=VALUE lines on stdin and merges them into ~/.hermes/.env.
# Python avoids treating token characters as sed replacement syntax. The script is shipped as
# base64 in argv (non-secret) so stdin stays free to carry secret values.
remote_script='from pathlib import Path
import os
import sys

env_file = Path.home() / ".hermes" / ".env"
env_file.parent.mkdir(parents=True, exist_ok=True)
existing = env_file.read_text().splitlines() if env_file.exists() else []
updates = {}
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if not line:
        continue
    key, value = line.split("=", 1)
    updates[key] = value

result = []
seen = set()
for line in existing:
    candidate = line.lstrip("# ").split("=", 1)[0]
    if candidate in updates:
        result.append(f"{candidate}={updates[candidate]}")
        seen.add(candidate)
    else:
        result.append(line)
for key, value in updates.items():
    if key not in seen:
        result.append(f"{key}={value}")

env_file.write_text("\n".join(result) + "\n")
os.chmod(env_file, 0o600)
print("  .env updated")'
script_b64="$(printf '%s' "$remote_script" | base64 | tr -d '\n')"
printf '%s\n' "${pairs[@]}" |
  ssh "$HOST" "f=\$(mktemp) && printf '%s' '$script_b64' | base64 --decode > \"\$f\" && python3 \"\$f\"; rm -f \"\$f\""

if [[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" ]]; then
  info "Enabling the bundled LINE platform plugin"
  ssh_host "$HOST" 'hermes config set gateway.platforms.line.enabled true >/dev/null'
fi

info "Installing + reloading the gateway service"
ssh_host "$HOST" '
  yes | hermes gateway install >/dev/null 2>&1 || true
  systemctl --user restart hermes-gateway.service
  for _ in $(seq 1 45); do
    state="$(systemctl --user is-active hermes-gateway.service 2>/dev/null || true)"
    if [ "$state" = active ]; then
      sleep 3
      [ "$(systemctl --user is-active hermes-gateway.service 2>/dev/null || true)" = active ] && break
    fi
    sleep 2
  done
  [ "$(systemctl --user is-active hermes-gateway.service 2>/dev/null || true)" = active ]
  hermes gateway status 2>&1 | head -5
'

./scripts/verify-runtime.sh "$HOST" --skip-web

ok "gateway configured — message your bot to test"
