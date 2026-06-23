#!/usr/bin/env bash
# Idempotently configure the Hermes Agent provider/model on the droplet.
# This prevents the "provider is set but model is blank" runtime failure class.
#
# Usage:
#   HERMES_PROVIDER=openai-codex HERMES_MODEL=openai/gpt-5.5 scripts/configure-model.sh [ssh-host]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

HOST="${1:-hermes-vps}"
HERMES_PROVIDER="${HERMES_PROVIDER:-openai-codex}"
HERMES_MODEL="${HERMES_MODEL:-openai/gpt-5.5}"
HERMES_CODEX_GPT55_AUTORAISE="${HERMES_CODEX_GPT55_AUTORAISE:-false}"

[[ -n "$HERMES_PROVIDER" ]] || die "HERMES_PROVIDER must not be empty"
[[ -n "$HERMES_MODEL" ]] || die "HERMES_MODEL must not be empty"
[[ "$HERMES_CODEX_GPT55_AUTORAISE" =~ ^(true|false)$ ]] || die "HERMES_CODEX_GPT55_AUTORAISE must be true or false"

info "Configuring Hermes provider/model on $HOST"
ssh_host "$HOST" "python3 - <<'PY'
from pathlib import Path
import re

path = Path.home() / '.hermes' / 'config.yaml'
text = path.read_text()

def set_yaml_scalar(src: str, key: str, value: str) -> str:
    pattern = re.compile(rf'^(  {re.escape(key)}:)\\s*.*$', re.MULTILINE)
    replacement = rf'\\1 \"{value}\"'
    if pattern.search(src):
        return pattern.sub(replacement, src, count=1)
    return src.replace('model:\\n', f'model:\\n  {key}: \"{value}\"\\n', 1)

text = set_yaml_scalar(text, 'provider', '${HERMES_PROVIDER}')
text = set_yaml_scalar(text, 'default', '${HERMES_MODEL}')
path.write_text(text)
PY
grep -E '^  (provider|default):' ~/.hermes/config.yaml"

ssh_host "$HOST" "hermes config set compression.codex_gpt55_autoraise ${HERMES_CODEX_GPT55_AUTORAISE} >/dev/null"

./scripts/verify-runtime.sh "$HOST" --skip-web
ok "Hermes provider/model configured"
