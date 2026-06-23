#!/usr/bin/env bash
# Validate infra configs locally before deploying. Skips checks whose tools are absent.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

rc=0

info "Validating infra/docker-compose.yml"
if command -v docker > /dev/null 2>&1; then
  if docker compose --env-file infra/.env.example -f infra/docker-compose.yml config --quiet; then
    ok "docker-compose is valid"
  else
    warn "docker-compose validation failed"
    rc=1
  fi
else
  warn "docker not installed locally — skipping compose validation (CI still enforces it)"
fi

info "Validating infra/Caddyfile"
if command -v caddy > /dev/null 2>&1; then
  if caddy validate --config infra/Caddyfile --adapter caddyfile > /dev/null 2>&1; then
    ok "Caddyfile is valid"
  else
    warn "Caddyfile validation failed"
    rc=1
  fi
elif command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1; then
  if docker run --rm -v "$PWD/infra/Caddyfile:/etc/caddy/Caddyfile:ro" \
    caddy:2 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile > /dev/null 2>&1; then
    ok "Caddyfile is valid"
  else
    warn "Caddyfile validation failed"
    rc=1
  fi
elif [[ -n "${CI:-}" ]]; then
  warn "neither local caddy nor a usable Docker daemon is available for Caddyfile validation"
  rc=1
else
  warn "skipping Caddyfile validation locally (install caddy or start Docker Desktop); CI still enforces it"
fi

info "Checking required infra files exist"
for f in infra/docker-compose.yml infra/Caddyfile infra/.env.example infra/hermes-agent.service; do
  [[ -f "$f" ]] && ok "$f" || {
    warn "missing: $f"
    rc=1
  }
done

[[ $rc -eq 0 ]] && ok "all validations passed" || die "validation failed (see warnings above)"
