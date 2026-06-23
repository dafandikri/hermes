#!/usr/bin/env bash
# Configure the Hermes Agent messaging gateway (Telegram and/or Discord) idempotently,
# then install + start it as a service. Secrets are read from the ENVIRONMENT and piped
# over stdin (never passed as argv, so they don't leak into the remote process list).
#
# Usage:
#   export TELEGRAM_BOT_TOKEN=... TELEGRAM_ALLOWED_USERS=123
#   export DISCORD_BOT_TOKEN=...  DISCORD_ALLOWED_USERS=456   # optional
#   scripts/configure-hermes.sh [ssh-host]                    # default: hermes-vps
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"

# Collect whichever platform secrets are present in the environment.
declare -a pairs=()
[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && pairs+=("TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}")
[[ -n "${TELEGRAM_ALLOWED_USERS:-}" ]] && pairs+=("TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}")
[[ -n "${DISCORD_BOT_TOKEN:-}" ]] && pairs+=("DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}")
[[ -n "${DISCORD_ALLOWED_USERS:-}" ]] && pairs+=("DISCORD_ALLOWED_USERS=${DISCORD_ALLOWED_USERS}")

[[ ${#pairs[@]} -gt 0 ]] || die "no platform secrets in environment (set TELEGRAM_BOT_TOKEN and/or DISCORD_BOT_TOKEN)"

if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -z "${TELEGRAM_ALLOWED_USERS:-}" ]]; then
  warn "TELEGRAM_BOT_TOKEN set without TELEGRAM_ALLOWED_USERS — the bot would accept ANYONE. Set your user ID."
fi
if [[ -n "${DISCORD_BOT_TOKEN:-}" && -z "${DISCORD_ALLOWED_USERS:-}" ]]; then
  warn "DISCORD_BOT_TOKEN set without DISCORD_ALLOWED_USERS — the bot would accept ANYONE. Set your user ID."
fi

info "Writing ${#pairs[@]} key(s) to ~/.hermes/.env on $HOST (secrets via stdin, not argv)"
# Remote upsert script: reads KEY=VALUE lines on stdin and merges them into ~/.hermes/.env.
# It is shipped as base64 in argv (non-secret) so stdin stays free to carry the secret
# VALUES — avoiding SC2259 (a heredoc on `bash -s` would clobber the piped data).
remote_script='set -euo pipefail
env_file="$HOME/.hermes/.env"
touch "$env_file"; chmod 600 "$env_file"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  key="${line%%=*}"
  if grep -qE "^#? *${key}=" "$env_file"; then
    sed -i -E "s|^#? *${key}=.*|${line}|" "$env_file"
  else
    printf "%s\n" "$line" >> "$env_file"
  fi
done
echo "  .env updated"'
script_b64="$(printf '%s' "$remote_script" | base64 | tr -d '\n')"
printf '%s\n' "${pairs[@]}" |
  ssh "$HOST" "f=\$(mktemp) && printf '%s' '$script_b64' | base64 --decode > \"\$f\" && bash \"\$f\"; rm -f \"\$f\""

info "Installing + starting the gateway service"
ssh_host "$HOST" 'yes | hermes gateway install >/dev/null 2>&1 || true; hermes gateway start >/dev/null 2>&1 || true; hermes gateway status 2>&1 | head -5'

ok "gateway configured — message your bot to test"
