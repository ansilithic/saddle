# Colors
GREEN := \033[32m
CYAN := \033[36m
YELLOW := \033[33m
GRAY := \033[90m
BOLD := \033[1m
RESET := \033[0m

# Config
BIN_DIR := /usr/local/bin
BINARY := saddle

.DEFAULT_GOAL := help
.PHONY: build install uninstall clean rebuild test completions help

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
install:
	@if [ ! -f .build/release/$(BINARY) ]; then \
		echo "$(YELLOW)No binary found.$(RESET) Run 'make build' first."; \
		exit 1; \
	fi
	@if [ ! -d $(BIN_DIR) ] || [ ! -w $(BIN_DIR) ]; then \
		echo "Setting up $(BIN_DIR) (requires sudo)..."; \
		sudo mkdir -p $(BIN_DIR); \
		sudo chown -R $$(whoami) $(BIN_DIR); \
	fi
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
	@mkdir -p completions
	@.build/release/$(BINARY) --generate-completion-script zsh > completions/_$(BINARY)
	@.build/release/$(BINARY) --generate-completion-script bash > completions/$(BINARY).bash
	@.build/release/$(BINARY) --generate-completion-script fish > completions/$(BINARY).fish
	@echo "$(GREEN)Completions generated in completions/$(RESET)"

# ============================================================
# Help
# ============================================================
help:
	@echo ""
	@echo "$(BOLD)Usage:$(RESET) make $(CYAN)[target]$(RESET)"
	@echo ""
	@echo "$(YELLOW)Targets:$(RESET)"
	@echo "  $(CYAN)build$(RESET)     $(GRAY)-$(RESET) $(GREEN)Build the release binary$(RESET)"
	@echo "  $(CYAN)install$(RESET)   $(GRAY)-$(RESET) $(GREEN)Copy binary to /usr/local/bin$(RESET)"
	@echo "  $(CYAN)rebuild$(RESET)   $(GRAY)-$(RESET) $(GREEN)Clean, build, and install$(RESET)"
	@echo "  $(CYAN)uninstall$(RESET) $(GRAY)-$(RESET) $(GREEN)Remove binary from /usr/local/bin$(RESET)"
	@echo "  $(CYAN)test$(RESET)      $(GRAY)-$(RESET) $(GREEN)Run tests$(RESET)"
	@echo "  $(CYAN)completions$(RESET) $(GRAY)-$(RESET) $(GREEN)Generate shell completions (zsh, bash, fish)$(RESET)"
	@echo "  $(CYAN)clean$(RESET)     $(GRAY)-$(RESET) $(GREEN)Remove build artifacts$(RESET)"
	@echo "  $(CYAN)help$(RESET)      $(GRAY)-$(RESET) $(GREEN)Show this help message (default)$(RESET)"
	@echo ""
