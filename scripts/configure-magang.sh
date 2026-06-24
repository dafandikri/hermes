#!/usr/bin/env bash
# Deploy the external magang application and install its managed Hermes instruction block.
#
# The application stays outside this public infrastructure repo because it contains private
# configuration, runtime logs, and university-owned DOCX templates.
#
# Usage:
#   MAGANG_SOURCE="/path/to/magang-tool" scripts/configure-magang.sh [ssh-host]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"
MAGANG_SOURCE="${MAGANG_SOURCE:-$HOME/Documents/Internship/Semester 7/magang-tool}"
REMOTE_HOME="magang"
SOUL_FRAGMENT="infra/hermes-soul-magang.md"

require_cmd rsync
[[ -d "$MAGANG_SOURCE/magang" ]] || die "magang source not found: $MAGANG_SOURCE"
[[ -f "$MAGANG_SOURCE/pyproject.toml" ]] || die "missing pyproject.toml in $MAGANG_SOURCE"
[[ -f "$MAGANG_SOURCE/config.example.yaml" ]] || die "missing config.example.yaml in $MAGANG_SOURCE"
[[ -f "$MAGANG_SOURCE/templates/log-magang.docx" ]] || die "missing Log Magang template"
[[ -f "$MAGANG_SOURCE/templates/kerangka-acuan.docx" ]] || die "missing Kerangka Acuan template"

info "Syncing magang application to $HOST:~/$REMOTE_HOME"
rsync -az --delete \
  --exclude '.venv/' \
  --exclude 'out/' \
  --exclude 'data/' \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude 'config.yaml' \
  --exclude '*.source.docx' \
  --exclude '.pytest_cache/' \
  --exclude 'docs/' \
  "$MAGANG_SOURCE/" "$HOST:$REMOTE_HOME/"

remote_setup='set -euo pipefail
cd "$HOME/magang"

packages=""
command -v soffice >/dev/null 2>&1 || command -v libreoffice >/dev/null 2>&1 \
  || packages="${packages} libreoffice-writer"
python3 -c "import ensurepip" >/dev/null 2>&1 || packages="${packages} python3-venv"
if [ -n "$packages" ]; then
  sudo apt-get update -qq
  # shellcheck disable=SC2086
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $packages >/dev/null
fi

if [ ! -x .venv/bin/pip ]; then
  rm -rf .venv
  python3 -m venv .venv
fi
./.venv/bin/pip install --quiet --upgrade pip
./.venv/bin/pip install --quiet -e .

mkdir -p data out "$HOME/.local/bin"
if [ ! -f config.yaml ]; then
  cp config.example.yaml config.yaml
  chmod 600 config.yaml
fi

cat > "$HOME/.local/bin/magang" <<'"'"'SHIM'"'"'
#!/usr/bin/env bash
set -euo pipefail
export MAGANG_HOME="$HOME/magang"
exec "$HOME/magang/.venv/bin/magang" "$@"
SHIM
chmod +x "$HOME/.local/bin/magang"
'
remote_setup_b64="$(printf '%s' "$remote_setup" | base64 | tr -d '\n')"
ssh_host "$HOST" "printf '%s' '$remote_setup_b64' | base64 --decode | bash"

info "Installing managed Hermes instructions"
fragment_b64="$(base64 < "$SOUL_FRAGMENT" | tr -d '\n')"
remote_soul='import base64
import re
from pathlib import Path

start = "<!-- BEGIN HERMES MANAGED: MAGANG -->"
end = "<!-- END HERMES MANAGED: MAGANG -->"
fragment = base64.b64decode("__FRAGMENT__").decode().strip()
path = Path.home() / ".hermes" / "SOUL.md"
path.parent.mkdir(parents=True, exist_ok=True)
text = path.read_text() if path.exists() else "# Hermes Agent Persona\n"
block = f"{start}\n{fragment}\n{end}"

if start in text and end in text:
    before, remainder = text.split(start, 1)
    _, after = remainder.split(end, 1)
    text = before.rstrip() + "\n\n" + block + after
else:
    # Migrate the original manually-installed section without disturbing later SOUL sections.
    text = re.sub(
        r"^## Magang logging tool \(`magang`\)\n.*?(?=^## |\Z)",
        "",
        text,
        flags=re.MULTILINE | re.DOTALL,
    ).rstrip()
    text = text.rstrip() + "\n\n" + block + "\n"

path.write_text(text)
'
remote_soul="${remote_soul//__FRAGMENT__/$fragment_b64}"
remote_soul_b64="$(printf '%s' "$remote_soul" | base64 | tr -d '\n')"
ssh_host "$HOST" "printf '%s' '$remote_soul_b64' | base64 --decode | python3"

./scripts/verify-magang.sh "$HOST"
ok "magang integration configured"
