# cwtch developer tasks.
#
# `make check` is the CI contract: it runs exactly the checks
# .github/workflows/ci.yml runs, in the same way, through the same targets.
# If you add a step to CI, add it here; if CI and this file diverge, CI stops
# being something you can reproduce locally.
#
# `e2e` is deliberately not part of `check`: it clones from github.com and
# writes to the real $HOME, so CI gives it a job of its own.
#
# Requires: shellcheck, shfmt, actionlint, bats, jq, yq. `make tools` reports
# the versions and fails if any of them is too old.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

SHFMT_FLAGS := -i 2 -ci

# Files are listed one by one rather than passing directories to shfmt and
# shellcheck: `shfmt bin/ lib/ tests/` also picks up tests/*.bats, which shfmt
# either rewrites into something bats will not run or refuses to parse at all
# ("`}` can only be used to close a block" on `@test "..." {`).
SHIPPED_SOURCES := bin/cwtch \
  lib/common.sh lib/config.sh lib/sync.sh \
  scripts/install.sh scripts/check-bash32.sh scripts/check-tools.sh
DEV_SOURCES := .devcontainer/setup.sh
SHELL_FILES := $(SHIPPED_SOURCES) $(DEV_SOURCES) tests/helpers.bash

E2E_SUITE := tests/e2e.bats
BATS_ALL := $(wildcard tests/*.bats)
BATS_UNIT := $(filter-out $(E2E_SUITE),$(BATS_ALL))
BATS := bats --print-output-on-failure

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-z0-9][a-z0-9-]*:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

.PHONY: check
check: lint fmt-check bash32-check test test-hermetic ## Run exactly what CI runs (not e2e)

.PHONY: tools
tools: ## Report the toolchain versions and enforce the minimums
	scripts/check-tools.sh

.PHONY: lint
lint: lint-shell lint-actions ## shellcheck the shell, actionlint the workflows

.PHONY: lint-shell
lint-shell: ## shellcheck the CLI, the libraries, the scripts and the test suite
	shellcheck -x $(SHIPPED_SOURCES) $(DEV_SOURCES)
	shellcheck -s bash tests/helpers.bash $(BATS_ALL)

.PHONY: lint-actions
lint-actions: ## actionlint the GitHub Actions workflows
	actionlint

.PHONY: fmt
fmt: ## Rewrite the shell sources with shfmt
	shfmt -w $(SHFMT_FLAGS) $(SHELL_FILES)

.PHONY: fmt-check
fmt-check: ## Fail if shfmt would change anything
	shfmt -d $(SHFMT_FLAGS) $(SHELL_FILES)

.PHONY: bash32-check
bash32-check: ## Prove the shipped scripts run under macOS' Bash 3.2
	scripts/check-bash32.sh $(SHIPPED_SOURCES)

.PHONY: test
test: tools ## Run the bats suite
	$(BATS) $(BATS_UNIT)

.PHONY: test-hermetic
test-hermetic: tools ## Run the bats suite with no system git config and no $USER
	GIT_CONFIG_NOSYSTEM=1 env -u USER $(BATS) $(BATS_UNIT)

.PHONY: e2e
e2e: tools ## Run the end-to-end suite (needs the network and the real $HOME)
	@[[ -f $(E2E_SUITE) ]] || { echo "$(E2E_SUITE) does not exist" >&2; exit 1; }
	CWTCH_E2E=1 $(BATS) $(E2E_SUITE)
