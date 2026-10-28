SHELL := $(shell command -v bash)
GIT_ROOT := $(shell git rev-parse --show-toplevel)
TOOLS_HOME := $(GIT_ROOT)/.tools
HOST_OS := $(shell uname -s | tr A-Z a-z)
HOST_ARCH := $(shell uname -m | sed -e 's/^x86_64$$/amd64/' -e 's/^aarch64$$/arm64/')
ifneq ($(filter $(HOST_OS),linux darwin),$(HOST_OS))
$(error Unsupported host OS: $(HOST_OS))
endif
ifneq ($(filter $(HOST_ARCH),amd64 arm64),$(HOST_ARCH))
$(error Unsupported host architecture: $(HOST_ARCH))
endif
VIRTUAL_ENV := $(TOOLS_HOME)/venv
GIT_PRE_COMMIT := $(GIT_ROOT)/.git/hooks/pre-commit

export VIRTUAL_ENV

ifndef VERBOSE
.SILENT:
endif

.PHONY: help
help: ## Show this help message
	grep -hE '^[%0-9a-zA-Z_/-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# ============================================================================
# Python/uv setup for pre-commit hooks
# ============================================================================

CURL := $(shell command -v curl)
$(CURL):
	$(error 'curl' could not be found on PATH. Please install curl)

ifeq ($(HOST_OS)/$(HOST_ARCH),linux/amd64)
UV_ARCH := x86_64-unknown-linux-gnu
else ifeq ($(HOST_OS)/$(HOST_ARCH),linux/arm64)
UV_ARCH := aarch64-unknown-linux-gnu
else ifeq ($(HOST_OS)/$(HOST_ARCH),darwin/amd64)
UV_ARCH := x86_64-apple-darwin
else ifeq ($(HOST_OS)/$(HOST_ARCH),darwin/arm64)
UV_ARCH := aarch64-apple-darwin
endif
UV_VERSION := 0.9.22
UV_ROOT := $(TOOLS_HOME)/uv-$(UV_VERSION)
UV := $(UV_ROOT)/uv-$(UV_ARCH)/uv
$(UV): | $(CURL)
	echo "Installing uv $(UV_VERSION)..."
	mkdir -p $(UV_ROOT)
	$(CURL) -Ls https://github.com/astral-sh/uv/releases/download/$(UV_VERSION)/uv-$(UV_ARCH).tar.gz | tar -xz -C $(UV_ROOT)

PYTHON_DEPS := $(VIRTUAL_ENV)/.python-deps-installed
$(PYTHON_DEPS): | $(UV)
	echo "Installing Python environment with uv..."
	$(UV) venv --clear $(VIRTUAL_ENV)
	$(UV) pip install 'pre-commit>=3.0.0'
	touch $@

PRE_COMMIT := $(VIRTUAL_ENV)/bin/pre-commit
$(PRE_COMMIT): | $(PYTHON_DEPS)

$(GIT_PRE_COMMIT): $(PRE_COMMIT)
	$(PRE_COMMIT) install

# ============================================================================
# Development Targets
# ============================================================================

.PHONY: deps
deps: $(PYTHON_DEPS) ## Install Python dependencies

.PHONY: hooks
hooks: $(GIT_PRE_COMMIT) ## Install pre-commit hooks

.PHONY: pre-commit
pre-commit: hooks ## Run pre-commit checks
	$(VIRTUAL_ENV)/bin/pre-commit run --all-files

# ============================================================================
# Cleanup
# ============================================================================

.PHONY: clean
clean: ## Remove build artifacts and tools
	echo "Cleaning up root..."
	rm -rf $(TOOLS_HOME)
	echo "✓ Cleanup complete"
