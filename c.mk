ZIG_VERSION ?= 0.17.0
CMAKE_VERSION ?= 4.4.4
NINJA_VERSION ?= 1.13.2
CLANG_FORMAT_VERSION ?= 23.1.3
MUNIT_VERSION ?= fbbdf1467eb0d04a6ee465def2e529e4c87f2118

BUILD_TYPE ?= Debug
BUILD_DIR ?= $(CURDIR)/build/$(BUILD_TYPE)
CMAKE_ARGS ?=
APP_NAME ?= $(notdir $(CURDIR))
RUN_ARGS ?=

.DEFAULT_GOAL := run

MKDIR := $(shell command -v mkdir)
MKTEMP := $(shell command -v mktemp)
MV := $(shell command -v mv)
RM := $(shell command -v rm)
TAR := $(shell command -v tar)
GIT := $(shell command -v git)
CHMOD := $(shell command -v chmod)
PRINTF := $(shell type -P printf)
TOUCH := $(shell command -v touch)

ifeq ($(HOST_OS),linux)
XZ := $(shell command -v xz)
ifeq ($(XZ),)
$(error 'xz' could not be found on PATH. Please install xz)
endif
endif

ifeq ($(HOST_ARCH),amd64)
ZIG_ARCH := x86_64
else ifeq ($(HOST_ARCH),arm64)
ZIG_ARCH := aarch64
endif
ifeq ($(HOST_OS),darwin)
ZIG_OS := macos
else
ZIG_OS := linux
endif

ZIG_ROOT := $(TOOLS_HOME)/zig-$(ZIG_VERSION)
ZIG := $(ZIG_ROOT)/zig
ZIG_CC := $(ZIG_ROOT)/wrap/zig-cc
ZIG_AR := $(ZIG_ROOT)/wrap/zig-ar
ZIG_RANLIB := $(ZIG_ROOT)/wrap/zig-ranlib

$(ZIG): | $(CURL)
	set -e -o pipefail; "$(MKDIR)" -p "$(TOOLS_HOME)"; \
	tmp=$$("$(MKTEMP)" -d "$(TOOLS_HOME)/.zig-install.XXXXXX"); trap '"$(RM)" -rf "$$tmp"' EXIT; \
	"$(CURL)" -fsSL "https://ziglang.org/download/$(ZIG_VERSION)/zig-$(ZIG_ARCH)-$(ZIG_OS)-$(ZIG_VERSION).tar.xz" | "$(TAR)" -xJ -C "$$tmp"; \
	test -x "$$tmp/zig-$(ZIG_ARCH)-$(ZIG_OS)-$(ZIG_VERSION)/zig"; \
	"$(MV)" "$$tmp/zig-$(ZIG_ARCH)-$(ZIG_OS)-$(ZIG_VERSION)" "$(ZIG_ROOT)"

$(ZIG_CC) $(ZIG_AR) $(ZIG_RANLIB): $(ZIG_ROOT)/wrap/zig-%: $(ZIG)
	set -e -o pipefail; "$(MKDIR)" -p "$(ZIG_ROOT)/wrap"; \
	tmp=$$("$(MKTEMP)" "$(ZIG_ROOT)/wrap/.zig-wrap.XXXXXX"); trap '"$(RM)" -f "$$tmp"' EXIT; \
	"$(PRINTF)" '%s\n' '#!/bin/sh' 'exec "$(ZIG)" $* "$$@"' > "$$tmp"; \
	"$(CHMOD)" +x "$$tmp"; "$(MV)" "$$tmp" "$@"

CMAKE_ROOT := $(TOOLS_HOME)/cmake-$(CMAKE_VERSION)
NINJA_ROOT := $(TOOLS_HOME)/ninja-$(NINJA_VERSION)
CLANG_FORMAT_ROOT := $(TOOLS_HOME)/clang-format-$(CLANG_FORMAT_VERSION)
CMAKE_STAMP := $(CMAKE_ROOT)/.installed
NINJA_STAMP := $(NINJA_ROOT)/.installed
CLANG_FORMAT_STAMP := $(CLANG_FORMAT_ROOT)/.installed
CMAKE := $(CMAKE_ROOT)/bin/cmake
CTEST := $(CMAKE_ROOT)/bin/ctest
NINJA := $(NINJA_ROOT)/bin/ninja
CLANG_FORMAT := $(CLANG_FORMAT_ROOT)/bin/clang-format
MUNIT_ROOT := $(TOOLS_HOME)/munit-$(MUNIT_VERSION)
MUNIT_STAMP := $(MUNIT_ROOT)/.installed
MUNIT_C := $(MUNIT_ROOT)/munit.c

define uv-install-tool
$(1)/.installed: | $(UV)
	set -e -o pipefail; "$(UV)" venv --clear "$(1)"; \
	"$(UV)" pip install --python "$(1)/bin/python" "$(2)"; \
	"$(TOUCH)" "$$@"
endef

$(eval $(call uv-install-tool,$(CMAKE_ROOT),cmake==$(CMAKE_VERSION)))
$(eval $(call uv-install-tool,$(NINJA_ROOT),ninja==$(NINJA_VERSION)))
$(eval $(call uv-install-tool,$(CLANG_FORMAT_ROOT),clang-format==$(CLANG_FORMAT_VERSION)))

$(CMAKE) $(CTEST): $(CMAKE_STAMP)
	test -x "$@"

$(NINJA): $(NINJA_STAMP)
	test -x "$@"

$(CLANG_FORMAT): $(CLANG_FORMAT_STAMP)
	test -x "$@"

$(MUNIT_STAMP): | $(CURL)
	set -e -o pipefail; "$(MKDIR)" -p "$(TOOLS_HOME)"; \
	tmp=$$("$(MKTEMP)" -d "$(TOOLS_HOME)/.munit-install.XXXXXX"); trap '"$(RM)" -rf "$$tmp"' EXIT; \
	"$(CURL)" -fsSL "https://raw.githubusercontent.com/nemequ/munit/$(MUNIT_VERSION)/munit.h" -o "$$tmp/munit.h"; \
	"$(CURL)" -fsSL "https://raw.githubusercontent.com/nemequ/munit/$(MUNIT_VERSION)/munit.c" -o "$$tmp/munit.c"; \
	test -s "$$tmp/munit.h"; test -s "$$tmp/munit.c"; \
	"$(TOUCH)" "$$tmp/.installed"; \
	"$(RM)" -rf "$(MUNIT_ROOT)"; "$(MV)" "$$tmp" "$(MUNIT_ROOT)"

$(BUILD_DIR)/build.ninja: $(CMAKE_STAMP) $(NINJA_STAMP) $(ZIG_CC) $(ZIG_AR) $(ZIG_RANLIB) $(MUNIT_STAMP)
	set -e -o pipefail; "$(CMAKE)" -S "$(CURDIR)" -B "$(BUILD_DIR)" -G Ninja \
		-DCMAKE_MAKE_PROGRAM="$(NINJA)" -DCMAKE_BUILD_TYPE="$(BUILD_TYPE)" \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
		-DCMAKE_C_COMPILER="$(ZIG_CC)" -DCMAKE_AR="$(ZIG_AR)" -DCMAKE_RANLIB="$(ZIG_RANLIB)" \
		-DMUNIT_INCLUDE_DIR="$(MUNIT_ROOT)" -DMUNIT_SOURCE="$(MUNIT_C)" \
		$(CMAKE_ARGS)

.PHONY: configure
configure: $(BUILD_DIR)/build.ninja ## Configure the CMake project

.PHONY: run
run: build ## Build and run the application
	"$(BUILD_DIR)/$(APP_NAME)" $(RUN_ARGS)

.PHONY: build
build: configure ## Build the CMake project
	"$(CMAKE)" --build "$(BUILD_DIR)"

.PHONY: test
test: build $(CTEST) ## Run CMake tests
	"$(CTEST)" --test-dir "$(BUILD_DIR)" --output-on-failure

.PHONY: test/full
test/full: build $(CTEST) ## Run CMake tests shuffled and repeated
	"$(CTEST)" --test-dir "$(BUILD_DIR)" --output-on-failure --schedule-random --repeat until-fail:2 --timeout 60

.PHONY: format
format: $(CLANG_FORMAT) ## Format C source files
	for f in $$($(GIT) ls-files '*.c' '*.h'); do "$(CLANG_FORMAT)" -i "$$f" || exit 1; done

.PHONY: format/check
format/check: $(CLANG_FORMAT) ## Check C source formatting
	for f in $$($(GIT) ls-files '*.c' '*.h'); do "$(CLANG_FORMAT)" --dry-run --Werror "$$f" || exit 1; done

.PHONY: tools/install
tools/install: $(ZIG) $(ZIG_CC) $(ZIG_AR) $(ZIG_RANLIB) $(CMAKE_STAMP) $(NINJA_STAMP) $(CLANG_FORMAT_STAMP) $(MUNIT_STAMP) ## Install repository-local C tools
