# Colors
GREEN := \033[32m
CYAN := \033[36m
YELLOW := \033[33m
GRAY := \033[90m
BOLD := \033[1m
RESET := \033[0m

# Config
BIN_DIR := /usr/local/bin
COMPLETIONS_DIR := $(shell zsh -c 'for d in $${fpath}; do if [[ "$$d" == $(HOME)/* ]] && [[ -d "$$d" ]] && [[ -w "$$d" ]]; then echo "$$d"; exit 0; fi; done; echo "$(HOME)/Library/Application Support/com.apple.zsh/completions"')
BINARY := saddle

.DEFAULT_GOAL := help
.PHONY: build build-debug install uninstall health clean rebuild test completions demo help

# ============================================================
# Build
# ============================================================
build:
	@echo "Building $(BINARY)..."
	@swift build -c release
	@echo "$(GREEN)Build complete!$(RESET) Binary at .build/release/$(BINARY)"

# ============================================================
# Build (debug) — needed for SADDLE_FORGE_MOCK support in demos
# ============================================================
build-debug:
	@echo "Building $(BINARY) (debug)..."
	@swift build
	@echo "$(GREEN)Debug build complete!$(RESET)"

# ============================================================
# Install
# ============================================================
install: completions
	@if [ ! -f .build/release/$(BINARY) ]; then \
		echo "$(YELLOW)No binary found.$(RESET) Run 'make build' first."; \
		exit 1; \
	fi
	@mkdir -p $(BIN_DIR)
	@echo "Installing $(BINARY) to $(BIN_DIR)..."
	@if [ -f $(BIN_DIR)/$(BINARY) ]; then rm $(BIN_DIR)/$(BINARY); fi
	@cp .build/release/$(BINARY) $(BIN_DIR)/$(BINARY)
	@echo "$(GREEN)Installed!$(RESET)"

# ============================================================
# Uninstall
# ============================================================
uninstall:
	@if [ -f $(BIN_DIR)/$(BINARY) ]; then \
		echo "Removing $(BIN_DIR)/$(BINARY)..."; \
		rm $(BIN_DIR)/$(BINARY); \
	else \
		echo "$(YELLOW)$(BINARY) not found in $(BIN_DIR).$(RESET)"; \
	fi
	@if [ -f "$(COMPLETIONS_DIR)/_$(BINARY)" ]; then \
		echo "Removing $(COMPLETIONS_DIR)/_$(BINARY)..."; \
		rm "$(COMPLETIONS_DIR)/_$(BINARY)"; \
	fi
	@echo "$(GREEN)Uninstalled!$(RESET)"

# ============================================================
# Health
# ============================================================
health:
	@if [ -x $(BIN_DIR)/$(BINARY) ]; then \
		echo "$(GREEN)$(BINARY) installed$(RESET)"; \
	else \
		echo "$(YELLOW)$(BINARY) not installed$(RESET)"; \
		exit 1; \
	fi

# ============================================================
# Rebuild (clean + build + install)
# ============================================================
rebuild: clean build install

# ============================================================
# Test
# ============================================================
test:
	@swift test

# ============================================================
# Clean
# ============================================================
clean:
	@echo "Cleaning build artifacts..."
	@swift package clean
	@rm -rf .build
	@echo "$(GREEN)Done!$(RESET)"

# ============================================================
# Completions
# ============================================================
completions:
	@if [ ! -f .build/release/$(BINARY) ]; then \
		echo "$(YELLOW)No binary found.$(RESET) Run 'make build' first."; \
		exit 1; \
	fi
	@mkdir -p "$(COMPLETIONS_DIR)"
	@.build/release/$(BINARY) completions > "$(COMPLETIONS_DIR)/_$(BINARY)"
	@echo "$(GREEN)Completions installed to $(COMPLETIONS_DIR)$(RESET)"
	@zsh -ic 'for d in $$fpath; do [ "$$d" = "$(COMPLETIONS_DIR)" ] && exit 0; done; exit 1' 2>/dev/null \
		|| echo "$(YELLOW)Warning:$(RESET) $(COMPLETIONS_DIR) is not in your fpath"

# ============================================================
# Demo — generate PNG screenshots and GIF recordings
# ============================================================
demo: build-debug
	@./scripts/demo.sh

# ============================================================
# Help
# ============================================================
help:
	@echo ""
	@echo "$(BOLD)Usage:$(RESET) make $(CYAN)[target]$(RESET)"
	@echo ""
	@echo "$(YELLOW)Targets:$(RESET)"
	@echo "  $(CYAN)build$(RESET)        $(GRAY)-$(RESET) $(GREEN)Build the release binary$(RESET)"
	@echo "  $(CYAN)install$(RESET)      $(GRAY)-$(RESET) $(GREEN)Copy binary to /usr/local/bin$(RESET)"
	@echo "  $(CYAN)rebuild$(RESET)      $(GRAY)-$(RESET) $(GREEN)Clean, build, and install$(RESET)"
	@echo "  $(CYAN)uninstall$(RESET)    $(GRAY)-$(RESET) $(GREEN)Remove binary from /usr/local/bin$(RESET)"
	@echo "  $(CYAN)health$(RESET)    $(GRAY)-$(RESET) $(GREEN)Check if binary is installed$(RESET)"
	@echo "  $(CYAN)test$(RESET)         $(GRAY)-$(RESET) $(GREEN)Run tests$(RESET)"
	@echo "  $(CYAN)completions$(RESET)  $(GRAY)-$(RESET) $(GREEN)Generate zsh completions$(RESET)"
	@echo "  $(CYAN)demo$(RESET)         $(GRAY)-$(RESET) $(GREEN)Generate PNG and GIF demo assets$(RESET)"
	@echo "  $(CYAN)clean$(RESET)        $(GRAY)-$(RESET) $(GREEN)Remove build artifacts$(RESET)"
	@echo "  $(CYAN)help$(RESET)         $(GRAY)-$(RESET) $(GREEN)Show this help message (default)$(RESET)"
	@echo ""
