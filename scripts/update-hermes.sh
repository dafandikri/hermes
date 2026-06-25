#!/usr/bin/env bash
# Update Hermes Agent, then restore and verify this repo's runtime invariants.
# Usage: scripts/update-hermes.sh [ssh-host]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"

info "Updating Hermes Agent on $HOST"
ssh_host "$HOST" 'hermes update'

./scripts/configure-model.sh "$HOST"
./scripts/status.sh "$HOST"

ok "Hermes Agent updated and runtime invariants restored"
