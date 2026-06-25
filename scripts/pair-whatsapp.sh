#!/usr/bin/env bash
# Pair Hermes's built-in WhatsApp/Baileys bridge. This is intentionally interactive:
# scan the displayed QR code from WhatsApp -> Settings -> Linked Devices.
#
# Use a dedicated bot number. Baileys is unofficial and carries account restriction risk.
# Usage: scripts/pair-whatsapp.sh [ssh-host]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"

info "Opening the Hermes WhatsApp pairing wizard on $HOST"
info "Scan the QR with the dedicated bot account; session credentials stay on the droplet"
ssh -t "$HOST" 'export PATH="$HOME/.local/bin:$PATH"; hermes whatsapp'

ssh_host "$HOST" 'chmod 700 ~/.hermes/whatsapp/session 2>/dev/null || true'
ok "WhatsApp pairing wizard completed"
