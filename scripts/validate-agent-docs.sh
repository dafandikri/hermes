#!/usr/bin/env bash
# Validate cross-agent instruction entrypoints stay present and non-conflicting.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

rc=0

for f in AGENTS.md CLAUDE.md OPENCODE.md; do
  if [[ -s "$f" ]]; then
    ok "$f exists"
  else
    warn "$f is missing or empty"
    rc=1
  fi
done

if grep -q "Universal working instructions" AGENTS.md; then
  ok "AGENTS.md is canonical"
else
  warn "AGENTS.md does not look like the canonical agent guide"
  rc=1
fi

if grep -q "AGENTS.md" CLAUDE.md && grep -q "AGENTS.md" OPENCODE.md; then
  ok "tool-specific entrypoints point to AGENTS.md"
else
  warn "CLAUDE.md and OPENCODE.md must point to AGENTS.md"
  rc=1
fi

if grep -q "make verify-runtime" AGENTS.md && grep -q "openai/gpt-5.5" AGENTS.md && grep -q "rtk-rewrite" AGENTS.md; then
  ok "runtime invariant is documented for agents"
else
  warn "AGENTS.md must document runtime verification, the active model, and RTK filtering"
  rc=1
fi

if grep -q "validate-current-design.sh" AGENTS.md && grep -q "docs/operations/mistakes.md" AGENTS.md; then
  ok "design/mistake-log enforcement is documented for agents"
else
  warn "AGENTS.md must document current-design and mistake-log enforcement"
  rc=1
fi

[[ "$rc" -eq 0 ]] && ok "agent docs validated" || die "agent docs validation failed"
