#!/usr/bin/env bash
# Idempotently ensure a swapfile exists on the droplet. The 2 GB box runs the bots,
# Open WebUI, and Caddy with little headroom; swap prevents the OOM-killer from shooting
# a live process during memory spikes (e.g. a web-UI build).
# Usage: scripts/ensure-swap.sh [ssh-host]   (default: hermes-vps)   SWAP_SIZE=2G
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"
SIZE="${SWAP_SIZE:-2G}"
require_cmd ssh

info "Ensuring ${SIZE} swap on ${HOST}"
ssh "$HOST" "SIZE='${SIZE}' bash -seu" << 'REMOTE'
if sudo swapon --show | grep -q '/swapfile'; then
  echo "  swap already active"
else
  if [ ! -f /swapfile ]; then
    sudo fallocate -l "$SIZE" /swapfile 2> /dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile > /dev/null
  fi
  sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
  echo "  swap enabled"
fi
free -h | awk '/Swap/ {print "  swap: total="$2" used="$3" free="$4}'
REMOTE

ok "swap ensured"
