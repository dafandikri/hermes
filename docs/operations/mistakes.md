# Mistake Log

This is the operating memory for failures we do not want to repeat.

Rule: every production-impacting mistake must have an entry with `Impact`, `Root Cause`,
`Guardrail`, and `Verification`. An entry is not complete until the guardrail is automated or
explicitly tied to a command in this repo.

## HERMES-001 Blank Codex Model

Impact: Hermes Agent was configured for `openai-codex`, but `model.default` was blank. Bot and web
sessions could open while the model path was not explicitly enforced.

Root Cause: The provider was changed from the original API-backed design to Codex OAuth, but the
model field was left to provider defaults instead of being pinned.

Guardrail: `scripts/configure-model.sh` enforces provider `openai-codex` and model
`openai/gpt-5.5`. `scripts/verify-runtime.sh` fails if provider/model drift or auth is logged out.

Verification: `make configure-model HOST=hermes-vps` and `make verify-runtime HOST=hermes-vps`.

## HERMES-002 Dashboard WebSocket Origin Mismatch

Impact: The dashboard loaded through Caddy, but interactive chat/PTY requests could fail because
WebSocket upgrades were rejected with an origin mismatch.

Root Cause: Caddy rewrote the upstream `Host` header to satisfy the dashboard DNS-rebinding guard,
but did not also rewrite the `Origin` header for upgraded requests.

Guardrail: `infra/Caddyfile.dashboard` rewrites both `Host` and `Origin` to the loopback dashboard
origin. `scripts/verify-runtime.sh` performs a raw WebSocket handshake against `/api/pty` and fails
unless the server returns `101 Switching Protocols`.

Verification: `make verify-runtime HOST=hermes-vps`.

## HERMES-003 Caddy Did Not Reload File-Only Changes

Impact: A corrected Caddyfile was written to disk, but the live Caddy process kept serving the old
in-memory config.

Root Cause: `docker compose up -d caddy` does not restart or reload a container when only the
contents of a bind-mounted config file change.

Guardrail: `scripts/switch-to-dashboard.sh` explicitly runs `caddy reload` after writing the
rendered Caddyfile.

Verification: `make dashboard HOST=hermes-vps` and `make verify-runtime HOST=hermes-vps`.

## HERMES-004 Docker Bind-Mount Inode Drift

Impact: The rendered Caddyfile looked correct on the host but Caddy still saw an older file.

Root Cause: In-place edits can replace the host file inode. A Docker bind mount may keep pointing at
the old inode until the container is recreated.

Guardrail: `scripts/switch-to-dashboard.sh` force-recreates Caddy after Caddyfile rendering, then
reloads Caddy and verifies the public endpoint.

Verification: `make dashboard HOST=hermes-vps`.

## HERMES-005 Codex Auto-Compaction Notice Repeated In Channels

Impact: Telegram/Discord sessions repeatedly displayed the Codex context-cap auto-compaction notice,
adding noise to normal assistant conversations.

Root Cause: Hermes Agent defaulted `compression.codex_gpt55_autoraise` to enabled for GPT-5.5.

Guardrail: Runtime config keeps `compression.enabled=true` for real auto-compaction and sets
`compression.codex_gpt55_autoraise=false` to suppress only the repeated auto-raise notice.
`scripts/verify-runtime.sh` fails if either value drifts.

Verification: `make verify-runtime HOST=hermes-vps`.

## HERMES-006 Remote Semgrep Packs Broke CI

Impact: CI could fail because a remote Semgrep pack was unavailable or renamed.

Root Cause: The workflow depended on moving external Semgrep pack names instead of repo-owned rules.

Guardrail: `.semgrep.yml` contains local rules and CI runs `semgrep --config .semgrep.yml`.

Verification: `make sast` and GitHub Actions `Static analysis (semgrep)`.

## HERMES-007 Non-Portable Bash Broke Local Runs

Impact: A script used features unavailable in the macOS default Bash, making the local harness
fragile on the owner's machine.

Root Cause: The script assumed a newer GNU Bash environment instead of the shell available on macOS.

Guardrail: Scripts are written with portable Bash patterns and checked by `shellcheck`; `make gate`
runs locally before commits and in CI before merge.

Verification: `make gate`.

## HERMES-008 Accidental Showcase Images In Repo

Impact: Local/generated images were added during experimentation and risked turning an infra repo
into an asset dump or creating unclear licensing/showcase signals.

Root Cause: The repo did not explicitly ignore common root-level image artifacts used during
conversation and UI experimentation.

Guardrail: `.gitignore` excludes root-level PNG/JPEG/WebP/GIF artifacts while allowing intentional
docs images under `docs/`.

Verification: `git status --short` and `make gate`.

## HERMES-009 Public Repo Operational Detail Risk

Impact: A public repo is useful for showcasing engineering quality, but operational detail can become
dangerous if it includes secrets, private keys, OAuth material, or passwords.

Root Cause: The project intentionally documents the live architecture, so the repo needs automated
boundaries around what may be public.

Guardrail: `gitleaks` runs in `make gate`, pre-commit, pre-push, and CI. `AGENTS.md` requires agents
to keep secrets only on the droplet or provider dashboards.

Verification: `make secrets-scan` and GitHub Actions `Quality gate`.

## HERMES-010 Gateway Self-Restart Loop In configure-rtk.sh

Impact: The Hermes gateway repeatedly shut down (16 restarts in one window, ~every 3m45s), dropping
Telegram/Discord availability mid-task and interrupting long-running agent commands.

Root Cause: `scripts/configure-rtk.sh` restarted the gateway with a direct
`systemctl --user restart hermes-gateway`. When the agent runs that script from inside the gateway
(self-host), the restart SIGTERMs the agent mid-command; systemd restarts it; the agent retries the
script, producing a restart loop.

Guardrail: The gateway restart in `scripts/configure-rtk.sh` is now detached and delayed via
`systemd-run --user --on-active=8`, so it fires after the current turn finishes instead of killing
the running agent. A direct restart remains only as a fallback when `systemd-run` is unavailable.

Verification: `systemctl --user show hermes-gateway -p NRestarts` stays stable after
`make configure-rtk HOST=hermes-vps`; `make gate`.

## HERMES-011 Verification Raced A Gateway Drain

Impact: A successful Hermes update was reported as failed because runtime verification observed
`hermes-gateway.service` in its expected transient `deactivating` state during the updater's drain
and delayed RTK restart.

Root Cause: `scripts/verify-runtime.sh` sampled systemd service state once. Update and plugin
workflows legitimately restart the gateway asynchronously, so a strict single sample could produce
a false negative while the service was converging.

Guardrail: Runtime verification now waits up to 90 seconds for the dashboard and gateway to become
active, then confirms each remains active after a two-second stability interval. It still fails if
either service does not converge.

Verification: `make update-hermes HOST=hermes-vps`, followed by
`make verify-runtime HOST=hermes-vps`.
