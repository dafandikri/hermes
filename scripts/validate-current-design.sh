#!/usr/bin/env bash
# Validate that committed docs and infra still describe the current deployed
# design. This catches stale docs and partial infra edits before they leave the
# machine.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source "scripts/lib.sh"

rc=0

require_text() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if grep -qE -- "$pattern" "$file"; then
    ok "$label"
  else
    warn "missing current-design invariant in $file: $label"
    rc=1
  fi
}

require_text docs/architecture.md 'provider: "openai-codex"' "architecture documents Codex provider"
require_text docs/architecture.md 'openai/gpt-5\.5' "architecture documents active model"
require_text docs/architecture.md 'compression\.enabled=true' "architecture documents auto-compression enabled"
require_text docs/architecture.md 'compression\.codex_gpt55_autoraise=false' \
  "architecture documents Codex auto-raise notice suppression"
require_text docs/architecture.md 'rtk-rewrite' "architecture documents RTK plugin"
require_text docs/architecture.md 'RTK_HERMES_MODE=rewrite' "architecture documents RTK rewrite mode"
require_text docs/architecture.md 'scripts/configure-magang\.sh' \
  "architecture documents idempotent magang deployment"
require_text docs/architecture.md 'scripts/verify-magang\.sh' \
  "architecture documents magang verification"
require_text docs/architecture.md 'LINE Messaging API' "architecture documents official LINE adapter"
require_text docs/architecture.md 'WhatsApp/Baileys' "architecture documents WhatsApp bridge and risk"
require_text docs/architecture.md 'scripts/verify-channels\.sh' \
  "architecture documents messaging channel verification"
require_text docs/architecture.md 'assistant\.dafandikri\.tech' "architecture documents public domain"
require_text docs/architecture.md 'network_mode: host' "architecture documents Caddy host networking"
require_text docs/architecture.md 'Host.*Origin|Origin.*Host' "architecture documents Host and Origin rewrites"
require_text docs/architecture.md 'basic-auth' "architecture documents edge basic-auth"
require_text docs/architecture.md 'docs/operations/mistakes\.md' "architecture documents mistake-log loop"

require_text README.md 'openai-codex' "README documents subscription-backed provider"
require_text README.md 'openai/gpt-5\.5' "README documents active model"
require_text README.md 'rtk-rewrite' "README documents RTK plugin"
require_text README.md 'docs/operations/mistakes\.md' "README links mistake log"
require_text README.md 'make verify-runtime' "README documents runtime guard"
require_text README.md 'make configure-magang' "README documents magang deployment"
require_text README.md 'make verify-magang' "README documents magang verification"
require_text README.md 'make configure-line-edge' "README documents LINE edge deployment"
require_text README.md 'make configure-line' "README documents hidden-input LINE activation"
require_text README.md 'make pair-whatsapp' "README documents WhatsApp pairing"
require_text README.md 'make verify-channels' "README documents channel verification"

require_text AGENTS.md 'rtk-rewrite' "agent guide requires RTK filtering"
require_text AGENTS.md 'docs/operations/mistakes\.md' "agent guide requires mistake logging"
require_text CONTRIBUTING.md 'validate mistake log' "contributing guide documents mistake-log gate"

require_text infra/docker-compose.yml 'network_mode: host' "compose keeps Caddy on host network"
require_text infra/Caddyfile.dashboard 'basic_auth' "dashboard Caddyfile keeps edge auth"
require_text infra/Caddyfile.dashboard 'reverse_proxy /line/\* 127\.0\.0\.1:8646' \
  "dashboard Caddyfile exposes only the LINE adapter path"
require_text infra/Caddyfile.dashboard '@dashboard not path /line/\*' \
  "dashboard auth excludes only the signed LINE route"
require_text infra/Caddyfile.dashboard 'reverse_proxy 127\.0\.0\.1:9119' \
  "dashboard Caddyfile proxies loopback dashboard"
require_text infra/Caddyfile.dashboard 'header_up Host 127\.0\.0\.1:9119' \
  "dashboard Caddyfile rewrites upstream Host"
require_text infra/Caddyfile.dashboard 'header_up Origin http://127\.0\.0\.1:9119' \
  "dashboard Caddyfile rewrites upstream Origin"
require_text infra/hermes-dashboard.service '--host 127\.0\.0\.1' \
  "dashboard service binds loopback"
require_text infra/hermes-dashboard.service '--port 9119' "dashboard service uses expected port"
require_text infra/hermes-dashboard.service '--skip-build' "dashboard service does not build under systemd"

require_text scripts/verify-runtime.sh 'Sec-WebSocket-Key' "runtime guard performs WebSocket handshake"
require_text scripts/verify-runtime.sh '101 Switching Protocols| 101 ' \
  "runtime guard requires WebSocket 101"
require_text scripts/verify-runtime.sh 'codex_gpt55_autoraise' \
  "runtime guard checks Codex auto-raise setting"
require_text scripts/verify-runtime.sh 'rtk-rewrite' "runtime guard checks RTK plugin"
require_text scripts/verify-runtime.sh 'verify-channels\.sh' \
  "runtime guard checks messaging allowlists and sessions"
require_text scripts/configure-hermes.sh 'LINE_CHANNEL_ACCESS_TOKEN' \
  "gateway configuration supports LINE"
require_text scripts/configure-line-interactive.sh 'read -r -s' \
  "LINE activation reads credentials with terminal echo disabled"
require_text scripts/configure-hermes.sh 'WHATSAPP_ALLOWED_USERS' \
  "gateway configuration supports WhatsApp"
require_text scripts/configure-rtk.sh 'seamusmore/rtk-rewrite' "RTK configuration installs plugin"
require_text scripts/configure-rtk.sh 'RTK_HERMES_MODE.*rewrite' "RTK configuration defaults to rewrite mode"
require_text scripts/configure-rtk.sh 'restart hermes-gateway.service' \
  "RTK configuration restarts gateway after plugin changes"
require_text infra/hermes-runtime.env.example 'RTK_HERMES_BACKENDS=local' \
  "runtime env example pins RTK to local backend"
require_text scripts/configure-model.sh 'HERMES_COMPRESSION_ENABLED.*true' \
  "model configuration enforces auto-compression"
require_text scripts/configure-model.sh 'HERMES_CODEX_GPT55_AUTORAISE.*false' \
  "model configuration suppresses the auto-raise notice"
require_text scripts/configure-magang.sh 'BEGIN HERMES MANAGED: MAGANG' \
  "magang configuration uses a managed SOUL block"
require_text scripts/configure-magang.sh "exclude 'config.yaml'" \
  "magang deployment preserves private runtime config"
require_text scripts/verify-magang.sh 'magang status' "magang guard checks the live CLI"
require_text infra/hermes-soul-magang.md 'magang build-log' \
  "managed Hermes instructions cover weekly document generation"
require_text .github/workflows/ci.yml 'schedule:' "CI includes scheduled maintenance"
require_text .github/dependabot.yml 'package-ecosystem: "github-actions"' \
  "Dependabot keeps GitHub Actions updated"

[ "$rc" -eq 0 ] || die "current design validation failed"
ok "current design docs/infra validated"
