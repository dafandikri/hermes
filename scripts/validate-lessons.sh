#!/usr/bin/env bash
# Validate the operational mistake log. The log is a guardrail: when we learn a
# production-impacting lesson, it must be captured with an automated prevention
# path and an explicit verification command.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

log_file="docs/operations/mistakes.md"

[ -s "$log_file" ] || die "$log_file is missing or empty"

required_ids=(
  HERMES-001
  HERMES-002
  HERMES-003
  HERMES-004
  HERMES-005
  HERMES-006
  HERMES-007
  HERMES-008
  HERMES-009
  HERMES-010
  HERMES-011
  HERMES-012
  HERMES-013
)

rc=0

for id in "${required_ids[@]}"; do
  if grep -qE "^## ${id} " "$log_file"; then
    ok "mistake entry present: $id"
  else
    warn "missing required mistake entry: $id"
    rc=1
  fi
done

if awk '
  function finish_entry() {
    if (id == "") {
      return
    }
    missing = ""
    if (!impact) {
      missing = missing " Impact"
    }
    if (!root_cause) {
      missing = missing " Root-Cause"
    }
    if (!guardrail) {
      missing = missing " Guardrail"
    }
    if (!verification) {
      missing = missing " Verification"
    }
    if (missing != "") {
      printf "%s is missing:%s\n", id, missing > "/dev/stderr"
      bad = 1
    }
  }

  /^## HERMES-[0-9][0-9][0-9] / {
    finish_entry()
    id = $2
    impact = root_cause = guardrail = verification = 0
    count++
    next
  }

  id != "" && /^Impact:/ { impact = 1 }
  id != "" && /^Root Cause:/ { root_cause = 1 }
  id != "" && /^Guardrail:/ { guardrail = 1 }
  id != "" && /^Verification:/ { verification = 1 }

  END {
    finish_entry()
    if (count == 0) {
      print "no HERMES-NNN entries found" > "/dev/stderr"
      bad = 1
    }
    exit bad
  }
' "$log_file"; then
  ok "every mistake entry has impact, root cause, guardrail, and verification"
else
  warn "one or more mistake entries are incomplete"
  rc=1
fi

duplicate_ids="$(
  grep -E '^## HERMES-[0-9]{3} ' "$log_file" |
    awk '{print $2}' |
    sort |
    uniq -d
)"
if [ -n "$duplicate_ids" ]; then
  warn "duplicate mistake IDs: $duplicate_ids"
  rc=1
else
  ok "mistake IDs are unique"
fi

if grep -nE "\b(TODO|TBD|FIXME)\b" "$log_file"; then
  warn "mistake log contains unresolved TODO/TBD/FIXME markers"
  rc=1
fi

if grep -nE "(sk-or-|xox[baprs]-|[0-9]{8,}:[A-Za-z0-9_-]{20,}|BEGIN OPENSSH PRIVATE KEY)" "$log_file"; then
  warn "mistake log appears to contain a secret-like token"
  rc=1
fi

[ "$rc" -eq 0 ] || die "mistake log validation failed"
ok "mistake log validated"
