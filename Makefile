# Hermes — development harness.
# Run `make` or `make help` for the target list.
.DEFAULT_GOAL := help
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

# Allow `make deploy-webapp HOST=hermes-vps`
HOST ?= hermes-vps

.PHONY: help setup gate lint fmt validate secrets-scan sast deploy-webapp status hooks ci

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## Install the toolchain (pre-commit via uv) and git hooks
	@command -v uv >/dev/null || { echo "uv is required: https://docs.astral.sh/uv/"; exit 1; }
	uv tool install --upgrade pre-commit
	pre-commit install
	pre-commit install-hooks
	@echo "✓ harness ready — run 'make lint'"

gate: ## THE deterministic quality gate (format, shellcheck, yaml, validate, secrets)
	./scripts/gate.sh

lint: ## Run all linters via pre-commit on every file
	pre-commit run --all-files

sast: ## Static analysis (semgrep) over scripts + infra
	uvx semgrep --config p/bash --config p/dockerfile --config p/secrets \
		--error --metrics=off scripts infra

fmt: ## Auto-format shell scripts in place
	pre-commit run shfmt --all-files || true

validate: ## Validate infra configs (compose, Caddyfile, hermes config)
	./scripts/validate-config.sh

secrets-scan: ## Scan the whole repo for committed secrets
	pre-commit run gitleaks --all-files

deploy-webapp: ## Deploy/refresh the Caddy + Open WebUI stack on HOST
	./scripts/deploy-webapp.sh "$(HOST)"

status: ## Health-check both tracks (webapp + Hermes Agent) on HOST
	./scripts/status.sh "$(HOST)"

hooks: ## Re-install git hooks (after cloning)
	pre-commit install

ci: lint validate ## What CI runs: lint + validate
