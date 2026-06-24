# Hermes — development harness.
# Run `make` or `make help` for the target list.
.DEFAULT_GOAL := help
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

# Allow `make deploy-webapp HOST=hermes-vps`
HOST ?= hermes-vps

.PHONY: help setup gate lint fmt validate validate-current-design validate-agent-docs validate-lessons secrets-scan sast deploy-webapp dashboard swap configure-model configure-rtk configure-magang configure-bots verify-magang verify-runtime status autopilot hooks ci

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## Install the toolchain (pre-commit via uv) and git hooks
	@command -v uv >/dev/null || { echo "uv is required: https://docs.astral.sh/uv/"; exit 1; }
	uv tool install --upgrade pre-commit
	pre-commit install
	pre-commit install --hook-type pre-push
	pre-commit install-hooks
	@echo "✓ harness ready — run 'make lint'"

gate: ## THE deterministic quality gate (format, shellcheck, yaml, design, docs, lessons, secrets)
	./scripts/gate.sh

lint: ## Run all linters via pre-commit on every file
	pre-commit run --all-files

sast: ## Static analysis (semgrep) over scripts + infra
	uvx semgrep --config .semgrep.yml --error --metrics=off scripts infra

fmt: ## Auto-format shell scripts in place
	pre-commit run shfmt --all-files || true

validate: ## Validate infra configs (compose, Caddyfile, hermes config)
	./scripts/validate-config.sh

validate-current-design: ## Validate docs and infra match the current deployed design
	./scripts/validate-current-design.sh

validate-agent-docs: ## Validate AGENTS/CLAUDE/OPENCODE instruction entrypoints
	./scripts/validate-agent-docs.sh

validate-lessons: ## Validate the operational mistake log has guardrails + verification
	./scripts/validate-lessons.sh

secrets-scan: ## Scan the whole repo for committed secrets
	pre-commit run gitleaks --all-files

deploy-webapp: ## Deploy/refresh the Caddy + Open WebUI stack on HOST
	./scripts/deploy-webapp.sh "$(HOST)"

dashboard: ## Switch the public web app to the subscription-powered Hermes dashboard on HOST
	./scripts/switch-to-dashboard.sh "$(HOST)"

swap: ## Ensure a swapfile exists on HOST
	./scripts/ensure-swap.sh "$(HOST)"

configure-model: ## Enforce Hermes provider/model on HOST
	./scripts/configure-model.sh "$(HOST)"

configure-rtk: ## Install/enable RTK terminal-output filtering on HOST
	./scripts/configure-rtk.sh "$(HOST)"

configure-magang: ## Deploy the external magang tool and wire it into Hermes on HOST
	./scripts/configure-magang.sh "$(HOST)"

configure-bots: ## Wire Telegram/Discord secrets (from env) + start the gateway on HOST
	./scripts/configure-hermes.sh "$(HOST)"

verify-magang: ## Verify the live magang CLI, templates, renderer, and Hermes instructions
	./scripts/verify-magang.sh "$(HOST)"

verify-runtime: ## Verify live Hermes invariants on HOST (model/auth/services/web gate)
	./scripts/verify-runtime.sh "$(HOST)"

status: ## Health-check both tracks (webapp + Hermes Agent) on HOST
	./scripts/status.sh "$(HOST)"

autopilot: ## Automated local maintenance: gate, SAST, runtime verify, status
	./scripts/auto-maintain.sh "$(HOST)"

hooks: ## Re-install git hooks (after cloning)
	pre-commit install
	pre-commit install --hook-type pre-push

ci: gate sast ## What CI runs: gate + SAST
