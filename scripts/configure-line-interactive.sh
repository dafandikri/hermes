#!/usr/bin/env bash
# Configure LINE without putting the channel token or secret in shell history.
# Values are read with terminal echo disabled and passed to configure-hermes.sh
# through the child environment, then unset.
#
# Usage: scripts/configure-line-interactive.sh [ssh-host]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"
DEFAULT_PUBLIC_URL="https://assistant.dafandikri.tech"

[[ -t 0 ]] || die "interactive terminal required"

printf 'LINE user ID (starts with U): '
IFS= read -r line_user_id
[[ "$line_user_id" =~ ^U[0-9A-Fa-f]{32}$ ]] || die "LINE user ID must be U followed by 32 hexadecimal characters"

printf 'New LINE channel access token (hidden): '
IFS= read -r -s line_token
printf '\n'
[[ -n "$line_token" ]] || die "LINE channel access token must not be empty"

printf 'New LINE channel secret (hidden): '
IFS= read -r -s line_secret
printf '\n'
[[ "$line_secret" =~ ^[0-9A-Fa-f]{32}$ ]] || die "LINE channel secret must be 32 hexadecimal characters"

printf 'Public URL [%s]: ' "$DEFAULT_PUBLIC_URL"
IFS= read -r line_public_url
line_public_url="${line_public_url:-$DEFAULT_PUBLIC_URL}"
[[ "$line_public_url" =~ ^https:// ]] || die "LINE public URL must use HTTPS"
[[ "$line_public_url" =~ ^https://[^/]+/?$ ]] ||
  die "LINE public URL must be the base origin only (example: ${DEFAULT_PUBLIC_URL}), without /line/webhook"
line_public_url="${line_public_url%/}"

./scripts/configure-line-edge.sh "$HOST"

LINE_CHANNEL_ACCESS_TOKEN="$line_token" \
  LINE_CHANNEL_SECRET="$line_secret" \
  LINE_ALLOWED_USERS="$line_user_id" \
  LINE_HOME_CHANNEL="$line_user_id" \
  LINE_PUBLIC_URL="$line_public_url" \
  ./scripts/configure-hermes.sh "$HOST"

unset line_token line_secret

printf '\nSet this URL in LINE Developers and enable Use webhook:\n'
printf '  %s/line/webhook\n' "$line_public_url"
ok "LINE configured; send the official account a test message"
