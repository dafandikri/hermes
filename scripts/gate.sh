#!/usr/bin/env bash
# THE deterministic gate — single source of truth, fast-to-slow so cheap failures surface first.
# Local: auto-fixes formatting. CI (CI=1): strict check, never mutates.
# Mirrors the boulder-coach gate convention, scoped to a bash/infra repo.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

shell_files=(scripts/*.sh)

if [ -n "${CI:-}" ]; then
  echo "▶ 1/5 format (CI: check)" && shfmt -i 2 -ci -sr -d "${shell_files[@]}"
else
  echo "▶ 1/5 format (local: auto-fix)" && shfmt -i 2 -ci -sr -w "${shell_files[@]}"
fi
echo "▶ 2/5 shellcheck" && shellcheck --severity=warning --external-sources "${shell_files[@]}"
echo "▶ 3/5 yaml lint" && yamllint -c .yamllint.yaml .
echo "▶ 4/5 validate infra" && ./scripts/validate-config.sh
echo "▶ 5/5 secret scan" && gitleaks dir --no-banner --redact --config .gitleaks.toml .

echo "✅ GATE PASSED"
