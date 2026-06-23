#!/usr/bin/env bash
# Local automation bundle for routine repo + live-runtime maintenance.
# It intentionally does not commit, push, rotate secrets, or make the repo public.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"

info "1/5 repo gate"
./scripts/gate.sh

info "2/5 static analysis"
if command -v uvx > /dev/null 2>&1; then
  uvx semgrep --config .semgrep.yml --error --metrics=off scripts infra
else
  warn "uvx not found; skipping Semgrep SAST"
fi

info "3/5 enforce model invariant"
./scripts/configure-model.sh "$HOST"

info "4/5 live runtime verification"
if [[ -n "${DASH_USER:-}" && -n "${DASH_PASS:-}" ]]; then
  ./scripts/verify-runtime.sh "$HOST"
else
  warn "DASH_USER/DASH_PASS not set; verifying non-web invariants only"
  ./scripts/verify-runtime.sh "$HOST" --skip-web
fi

info "5/5 status summary"
./scripts/status.sh "$HOST"

ok "automated maintenance passed"
