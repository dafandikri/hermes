#!/usr/bin/env bash
# THE deterministic gate — single source of truth, fast-to-slow so cheap failures surface first.
# Local: auto-fixes formatting. CI (CI=1): strict check, never mutates.
# Mirrors the boulder-coach gate convention, scoped to a bash/infra repo.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

shell_files=(scripts/*.sh)

if [ -n "${CI:-}" ]; then
  echo "▶ 1/8 format (CI: check)" && shfmt -i 2 -ci -sr -d "${shell_files[@]}"
else
  echo "▶ 1/8 format (local: auto-fix)" && shfmt -i 2 -ci -sr -w "${shell_files[@]}"
fi
echo "▶ 2/8 shellcheck" && shellcheck --severity=warning --external-sources "${shell_files[@]}"
echo "▶ 3/8 yaml lint" && yamllint -c .yamllint.yaml .
echo "▶ 4/8 validate infra" && ./scripts/validate-config.sh
echo "▶ 5/8 validate current design" && ./scripts/validate-current-design.sh
echo "▶ 6/8 validate agent docs" && ./scripts/validate-agent-docs.sh
echo "▶ 7/8 validate mistake log" && ./scripts/validate-lessons.sh
echo "▶ 8/8 secret scan" && gitleaks dir --no-banner --redact --config .gitleaks.toml .

echo "✅ GATE PASSED"
