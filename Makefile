# Colors
GREEN := \033[32m
CYAN := \033[36m
YELLOW := \033[33m
GRAY := \033[90m
BOLD := \033[1m
RESET := \033[0m

# Config
BIN_DIR := $(HOME)/.local/bin
COMPLETIONS_DIR := $(HOME)/.local/share/zsh/completions
BINARY := saddle

.DEFAULT_GOAL := help
.PHONY: build install uninstall health clean rebuild test demo completions help

# ============================================================
# Build
# ============================================================
build:
	@echo "Building $(BINARY)..."
	@swift build -c release
	@echo "$(GREEN)Build complete!$(RESET) Binary at .build/release/$(BINARY)"

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
		echo "$(GREEN)Uninstalled!$(RESET)"; \
	else \
		echo "$(YELLOW)$(BINARY) not found in $(BIN_DIR).$(RESET)"; \
	fi

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
# Demo (fake data for screenshots)
# ============================================================
demo: build
	@./scripts/demo.sh setup
	@echo ""
	@PATH=".build/release:$$PATH" ./scripts/demo.sh run

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
	@mkdir -p completions
	@.build/release/$(BINARY) completions > completions/_$(BINARY)
	@mkdir -p $(COMPLETIONS_DIR)
	@cp completions/_$(BINARY) $(COMPLETIONS_DIR)/_$(BINARY)
	@echo "$(GREEN)Completions installed to $(COMPLETIONS_DIR)$(RESET)"

# ============================================================
# Help
# ============================================================
help:
	@echo ""
	@echo "$(BOLD)Usage:$(RESET) make $(CYAN)[target]$(RESET)"
	@echo ""
	@echo "$(YELLOW)Targets:$(RESET)"
	@echo "  $(CYAN)build$(RESET)        $(GRAY)-$(RESET) $(GREEN)Build the release binary$(RESET)"
	@echo "  $(CYAN)install$(RESET)      $(GRAY)-$(RESET) $(GREEN)Copy binary to ~/.local/bin$(RESET)"
	@echo "  $(CYAN)rebuild$(RESET)      $(GRAY)-$(RESET) $(GREEN)Clean, build, and install$(RESET)"
	@echo "  $(CYAN)uninstall$(RESET)    $(GRAY)-$(RESET) $(GREEN)Remove binary from ~/.local/bin$(RESET)"
	@echo "  $(CYAN)health$(RESET)    $(GRAY)-$(RESET) $(GREEN)Check if binary is installed$(RESET)"
	@echo "  $(CYAN)demo$(RESET)         $(GRAY)-$(RESET) $(GREEN)Run with fake data for screenshots$(RESET)"
	@echo "  $(CYAN)test$(RESET)         $(GRAY)-$(RESET) $(GREEN)Run tests$(RESET)"
	@echo "  $(CYAN)completions$(RESET)  $(GRAY)-$(RESET) $(GREEN)Generate zsh completions$(RESET)"
	@echo "  $(CYAN)clean$(RESET)        $(GRAY)-$(RESET) $(GREEN)Remove build artifacts$(RESET)"
	@echo "  $(CYAN)help$(RESET)         $(GRAY)-$(RESET) $(GREEN)Show this help message (default)$(RESET)"
	@echo ""
