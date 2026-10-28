include $(dir $(lastword $(MAKEFILE_LIST)))base.mk

GO_VERSION ?= 1.26.1
GO_ROOT := $(TOOLS_HOME)/go-$(GO_VERSION)
GO := $(GO_ROOT)/bin/go
GOFMT := $(GO_ROOT)/bin/gofmt
APP_NAME ?= $(notdir $(CURDIR))
BIN_DIR ?= $(CURDIR)/bin

export GOTOOLCHAIN := local

MKDIR := $(shell command -v mkdir)
MKTEMP := $(shell command -v mktemp)
MV := $(shell command -v mv)
RM := $(shell command -v rm)
TAR := $(shell command -v tar)
GIT := $(shell command -v git)
DIFF := $(shell command -v diff)
CHMOD := $(shell command -v chmod)

$(GO): | $(CURL)
	set -e -o pipefail; $(MKDIR) -p "$(TOOLS_HOME)"; \
	tmp=$$($(MKTEMP) -d "$(TOOLS_HOME)/.go-install.XXXXXX"); trap '$(RM) -rf "$$tmp"' EXIT; \
	"$(CURL)" -fsSL "https://go.dev/dl/go$(GO_VERSION).$(HOST_OS)-$(HOST_ARCH).tar.gz" | "$(TAR)" -xz -C "$$tmp"; \
	test -x "$$tmp/go/bin/go"; test -x "$$tmp/go/bin/gofmt"; \
	"$(MV)" "$$tmp/go" "$(GO_ROOT)"

$(GOFMT): $(GO)
	test -x "$@"

define go-install-tool
$(1): | $(GO)
	set -e -o pipefail; $(MKDIR) -p "$(dir $(1))"; \
	tmp=$$$$($(MKTEMP) -d "$(TOOLS_HOME)/.tool-install.XXXXXX"); trap '$(RM) -rf "$$$$tmp"' EXIT; \
	GOBIN="$$$$tmp" "$(GO)" install "$(2)"; \
	test -x "$$$$tmp/$(notdir $(1))"; "$(MV)" "$$$$tmp/$(notdir $(1))" "$$@"
endef

.PHONY: build
build: $(GO) ## Build the application
	"$(MKDIR)" -p "$(BIN_DIR)"
	CGO_ENABLED=0 "$(GO)" build -o "$(BIN_DIR)/$(APP_NAME)" .

.PHONY: test
test: $(GO) ## Run Go tests with race detector
	"$(GO)" test -race ./...

.PHONY: test/full
test/full: $(GO) ## Run Go tests shuffled and repeated
	"$(GO)" test -race -shuffle=on -count=2 -timeout 60s ./...

.PHONY: format
format: $(GOFMT) ## Format source files
	for f in $$($(GIT) ls-files '*.go'); do "$(GOFMT)" -w "$$f"; done

.PHONY: format/check
format/check: $(GOFMT) ## Check source formatting
	for f in $$($(GIT) ls-files '*.go'); do test -z "$$($(GOFMT) -l "$$f")" || { printf 'Unformatted: %s\n' "$$f"; exit 1; }; done

.PHONY: tools/install
tools/install: $(GO) $(GOFMT) ## Install repository-local Go tools
