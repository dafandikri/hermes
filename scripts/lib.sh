#!/usr/bin/env bash
# Shared helpers for hermes deploy/ops scripts. Source, don't execute.
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Colors (disabled when not a TTY).
if [[ -t 1 ]]; then
  _C_RED=$'\033[31m'
  _C_GRN=$'\033[32m'
  _C_YEL=$'\033[33m'
  _C_CYN=$'\033[36m'
  _C_RST=$'\033[0m'
else
  _C_RED=''
  _C_GRN=''
  _C_YEL=''
  _C_CYN=''
  _C_RST=''
fi

info() { printf '%s==>%s %s\n' "$_C_CYN" "$_C_RST" "$*"; }
ok() { printf '%s ✓ %s%s\n' "$_C_GRN" "$*" "$_C_RST"; }
warn() { printf '%s ! %s%s\n' "$_C_YEL" "$*" "$_C_RST" >&2; }
die() {
  printf '%s ✗ %s%s\n' "$_C_RED" "$*" "$_C_RST" >&2
  exit 1
}

# require_cmd <command> — fail with a helpful message if missing.
require_cmd() {
  command -v "$1" > /dev/null 2>&1 || die "required command not found: $1"
}

# ssh_host <host> <remote-command...> — run a command on the droplet over the SSH alias.
# PATH is exported so the user-installed `hermes` CLI is reachable.
ssh_host() {
  local host="$1"
  shift
  require_cmd ssh
  ssh "$host" "export PATH=\$HOME/.local/bin:\$PATH; $*"
}
