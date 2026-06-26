#!/usr/bin/env bash
# Verify the deployed magang CLI, document renderer prerequisites, and Hermes instructions.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"

info "Verifying magang integration on $HOST"

magang_path="$(ssh_host "$HOST" 'command -v magang 2>/dev/null || true')"
[[ "$magang_path" == "$HOME/.local/bin/magang" || "$magang_path" == "/home/hermes/.local/bin/magang" ]] ||
  die "magang CLI is missing from PATH: ${magang_path:-missing}"
ok "magang CLI available ($magang_path)"

office_path="$(ssh_host "$HOST" 'command -v soffice 2>/dev/null || command -v libreoffice 2>/dev/null || true')"
[[ -n "$office_path" ]] || die "LibreOffice is missing; PDF generation cannot run"
ok "PDF renderer available ($office_path)"

ssh_host "$HOST" 'test -f ~/magang/templates/log-magang.docx'
ssh_host "$HOST" 'test -f ~/magang/templates/kerangka-acuan.docx'
ok "official document templates available"

if ! ssh_host "$HOST" \
  'test -d ~/magang/data && find ~/magang/data -maxdepth 1 -type f -name "pekan-*.yaml" -readable -print -quit | grep -q .'; then
  die "magang sync interface has no readable weekly log"
fi
if ! ssh_host "$HOST" 'test -f ~/magang/config.yaml'; then
  die "magang sync interface config is missing"
fi
if ! ssh_host "$HOST" 'test "$(stat -c %a ~/magang/config.yaml)" = 600'; then
  die "magang config must have mode 600"
fi
ok "magang sync interface available"

status_output="$(ssh_host "$HOST" 'magang status')"
[[ -n "$status_output" ]] || die "magang status returned no output"
ok "magang data/config load successfully"

ssh_host "$HOST" 'grep -q "<!-- BEGIN HERMES MANAGED: MAGANG -->" ~/.hermes/SOUL.md'
ssh_host "$HOST" 'grep -q "<!-- END HERMES MANAGED: MAGANG -->" ~/.hermes/SOUL.md'
ok "Hermes magang instruction block installed"

ok "magang integration verified"
