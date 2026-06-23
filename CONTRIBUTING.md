# Contributing

This repo is infrastructure-as-code (bash, YAML, Docker, Caddy) with an enforced gate.

## Setup

```bash
make setup        # uv-installs pre-commit, installs git hooks + hook tools
```

You also need the binary linters on PATH for `make gate`:
`shellcheck`, `shfmt`, `yamllint`, `gitleaks` (macOS: `brew install shellcheck shfmt gitleaks`;
`yamllint` via `uv tool install yamllint`).

## The gate — single source of truth

[`scripts/gate.sh`](scripts/gate.sh) is THE gate. It runs fast-to-slow so cheap failures surface
first, auto-fixes formatting locally, and is strict (`CI=1`, no mutation) in CI:

1. **format** — `shfmt` (auto-fix local / check CI)
2. **shellcheck** — `--severity=warning --external-sources`
3. **yaml lint** — `yamllint -c .yamllint.yaml`
4. **validate infra** — `docker compose config` + `caddy validate`
5. **secret scan** — `gitleaks`

```bash
make gate     # run it
make sast     # semgrep static analysis (separate, slower)
make verify-runtime HOST=hermes-vps  # live runtime invariants after deploy changes
```

`pre-commit` runs the same linters on staged files at commit time. CI (`.github/workflows/ci.yml`)
runs `gate.sh` strict + semgrep on every push/PR.

`make verify-runtime` is the live-system guard. Run it after any change that touches Hermes Agent
provider/model, dashboard, Caddy, or gateway behavior. It fails on false-green states such as
`openai-codex` with a blank model.

## Conventions

- **Shell:** `#!/usr/bin/env bash`, `set -euo pipefail`, 2-space indent, quote expansions.
  Shared helpers live in [`scripts/lib.sh`](scripts/lib.sh) (`info/ok/warn/die`, `ssh_host`).
- **Idempotent ops:** scripts can be re-run safely; they refuse to act on missing prerequisites.
- **Secrets via environment, never argv** — see `configure-hermes.sh` (secrets piped over stdin).
- **No secrets in git** — only `infra/.env.example` placeholders; `gitleaks` enforces it.

## Before you commit

```bash
make gate     # must print "✅ GATE PASSED"
make verify-runtime HOST=hermes-vps  # after live infra changes
```
