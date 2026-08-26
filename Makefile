# Grid — the targets CI runs, so local and CI cannot disagree.

FLUTTER ?= flutter
APP     := app

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# --- the gate ---------------------------------------------------------------

.PHONY: ci
ci: doc-check analyze test coverage-gate ## Everything CI runs

.PHONY: gates
gates: doc-check coverage-gate ## The blocking gates alone. These never go yellow.

# --- code -------------------------------------------------------------------

.PHONY: setup
setup: ## Install dependencies and run code generation
	cd $(APP) && $(FLUTTER) pub get
	cd $(APP) && dart run build_runner build --delete-conflicting-outputs

.PHONY: gen
gen: ## Re-run code generation (Drift tables, Riverpod providers)
	cd $(APP) && dart run build_runner build --delete-conflicting-outputs

.PHONY: analyze
analyze: ## Static analysis, plus the domain-purity check
	cd $(APP) && $(FLUTTER) analyze
	@$(MAKE) --no-print-directory domain-purity

.PHONY: domain-purity
domain-purity: ## Fail if the domain layer imports Flutter
	@if grep -rl "package:flutter/" $(APP)/lib/domain 2>/dev/null | grep -q .; then \
	  echo "\033[0;31m✗\033[0m the domain layer imports Flutter:"; \
	  grep -rl "package:flutter/" $(APP)/lib/domain; \
	  echo "  The engines must stay pure Dart — testable without a device,"; \
	  echo "  identical on every platform. See ADR-0002."; \
	  exit 1; \
	fi
	@echo "\033[0;32m✓\033[0m domain layer is pure Dart"

.PHONY: test
test: ## Run the test suite
	cd $(APP) && $(FLUTTER) test

.PHONY: coverage
coverage: ## Run tests with coverage and print the per-file breakdown
	cd $(APP) && $(FLUTTER) test --coverage
	@python3 scripts/coverage-report.py $(APP)/coverage/lcov.info

.PHONY: coverage-gate
coverage-gate: ## Fail if the domain engines drop below 95%
	cd $(APP) && $(FLUTTER) test --coverage >/dev/null
	@python3 scripts/coverage-report.py $(APP)/coverage/lcov.info --gate 95 --only /domain/services/

.PHONY: run
run: ## Run on the attached device
	cd $(APP) && $(FLUTTER) run

# --- documentation ----------------------------------------------------------

.PHONY: doc-check
doc-check: ## Verify the documentation is present, well-formed and current
	@scripts/doc-check.sh

.PHONY: adr
adr: ## Scaffold the next ADR:  make adr T="the decision"
	@scripts/new-adr.sh "$(T)"

.PHONY: journal
journal: ## Add a session entry:  make journal T="what this session was about"
	@scripts/journal.sh "$(T)"

.PHONY: hooks
hooks: ## Install the git hooks
	@git config core.hooksPath .githooks
	@echo "\033[0;32m✓\033[0m hooks installed (core.hooksPath = .githooks)"

.PHONY: phase
phase: ## Print the current phase and its exit gate
	@p=$$(cat PHASE); \
	echo "Phase $$p"; \
	awk -v want="## Phase $$p" '$$0 ~ want {inside=1} /^## Phase/ && $$0 !~ want {inside=0} inside' docs/ROADMAP.md \
	  | grep -A6 '^\*\*Exit gate\*\*' || true

# --- Docker: reproducible Android builds ------------------------------------
# iOS is deliberately absent — Xcode does not run in a container. See Dockerfile.

.PHONY: docker-verify docker-apk docker-shell

docker-verify: ## analyze + the full suite on the pinned toolchain
	docker compose run --rm verify

docker-apk: ## build/grid-debug.apk, without Flutter installed on the host
	@mkdir -p build
	docker compose run --rm apk

docker-shell: ## a toolchain prompt
	docker compose run --rm shell
