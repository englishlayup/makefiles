include $(dir $(lastword $(MAKEFILE_LIST)))go.mk

TEMPL_VERSION ?= v0.3.1020
SQLC_VERSION ?= v1.31.1
TEMPLUI_VERSION ?= v1.3.0
AIR_VERSION ?= v1.63.1
TAILWINDCSS_VERSION ?= v4.2.2

TEMPL := $(TOOLS_HOME)/templ-$(TEMPL_VERSION)/templ
SQLC := $(TOOLS_HOME)/sqlc-$(SQLC_VERSION)/sqlc
TEMPLUI := $(TOOLS_HOME)/templui-$(TEMPLUI_VERSION)/templui
AIR := $(TOOLS_HOME)/air-$(AIR_VERSION)/air
TAILWINDCSS := $(TOOLS_HOME)/tailwindcss-$(TAILWINDCSS_VERSION)/tailwindcss

ifeq ($(HOST_OS)/$(HOST_ARCH),linux/amd64)
TAILWINDCSS_ASSET := tailwindcss-linux-x64
else ifeq ($(HOST_OS)/$(HOST_ARCH),linux/arm64)
TAILWINDCSS_ASSET := tailwindcss-linux-arm64
else ifeq ($(HOST_OS)/$(HOST_ARCH),darwin/amd64)
TAILWINDCSS_ASSET := tailwindcss-macos-x64
else ifeq ($(HOST_OS)/$(HOST_ARCH),darwin/arm64)
TAILWINDCSS_ASSET := tailwindcss-macos-arm64
endif

TAILWIND_INPUT ?= ./assets/css/inputs.css
TAILWIND_OUTPUT ?= ./assets/css/styles.css
DEV_ARGS ?=
LIVE_PROXY_TARGET ?= http://localhost:8080

$(eval $(call go-install-tool,$(TEMPL),github.com/a-h/templ/cmd/templ@$(TEMPL_VERSION)))
$(eval $(call go-install-tool,$(SQLC),github.com/sqlc-dev/sqlc/cmd/sqlc@$(SQLC_VERSION)))
$(eval $(call go-install-tool,$(TEMPLUI),github.com/templui/templui/cmd/templui@$(TEMPLUI_VERSION)))
$(eval $(call go-install-tool,$(AIR),github.com/air-verse/air@$(AIR_VERSION)))

$(TAILWINDCSS): | $(CURL)
	set -e -o pipefail; "$(MKDIR)" -p "$(dir $(TAILWINDCSS))"; \
	tmp=$$($(MKTEMP) "$(dir $(TAILWINDCSS)).tailwindcss-install.XXXXXX"); trap '$(RM) -f "$$tmp"' EXIT; \
	"$(CURL)" -fsSL -o "$$tmp" "https://github.com/tailwindlabs/tailwindcss/releases/download/$(TAILWINDCSS_VERSION)/$(TAILWINDCSS_ASSET)"; \
	"$(CHMOD)" +x "$$tmp"; "$(MV)" "$$tmp" "$@"

.PHONY: generate
generate: generate/templ generate/sqlc generate/tailwind ## Generate templ, sqlc, and Tailwind assets

.PHONY: generate/templ
generate/templ: $(TEMPL)
	"$(TEMPL)" generate

.PHONY: generate/sqlc
generate/sqlc: $(SQLC)
	"$(SQLC)" generate

.PHONY: generate/tailwind
generate/tailwind: $(TAILWINDCSS)
	"$(TAILWINDCSS)" -i "$(TAILWIND_INPUT)" -o "$(TAILWIND_OUTPUT)" --minify

format: format/templ

.PHONY: format/templ
format/templ: $(TEMPL)
	"$(TEMPL)" fmt .

format/check: format/check/templ

.PHONY: format/check/templ
format/check/templ: $(TEMPL)
	set -e -o pipefail; for f in $$($(GIT) ls-files '*.templ'); do \
		"$(TEMPL)" fmt -stdout -stdin-filepath "$$f" "$$f" | "$(DIFF)" -u "$$f" - || exit 1; \
	done

tools/install: $(TEMPL) $(SQLC) $(TEMPLUI) $(AIR) $(TAILWINDCSS)

.PHONY: all
all: generate build ## Generate assets and build the application

.PHONY: live/templ
live/templ: $(TEMPL)
	"$(TEMPL)" generate --watch --proxy="$(LIVE_PROXY_TARGET)" --open-browser=false -v

.PHONY: live/server
live/server: $(GO) $(AIR)
	"$(AIR)" \
	--build.cmd "$(MKDIR) -p tmp/bin && CGO_ENABLED=0 $(GO) build -o tmp/bin/main" --build.bin "tmp/bin/main" --build.args_bin "$(DEV_ARGS)" --build.delay "100" \
	--build.exclude_dir "node_modules,$(notdir $(TOOLS_HOME)),tmp" \
	--build.include_ext "go" \
	--build.stop_on_error "false" \
	--misc.clean_on_exit true

.PHONY: live/tailwind
live/tailwind: $(TAILWINDCSS)
	"$(TAILWINDCSS)" -i "$(TAILWIND_INPUT)" -o "$(TAILWIND_OUTPUT)" --minify --watch

.PHONY: live/sync-assets
live/sync-assets: $(TEMPL) $(AIR)
	"$(AIR)" \
	--build.cmd "$(TEMPL) generate --notify-proxy" \
	--build.bin "true" \
	--build.delay "100" \
	--build.exclude_dir "" \
	--build.include_dir "assets" \
	--build.include_ext "js,css"

.PHONY: live
live: $(GO) $(TEMPL) $(AIR) $(TAILWINDCSS) ## Start the development server and asset watchers
	$(MAKE) -j4 live/templ live/server live/tailwind live/sync-assets
