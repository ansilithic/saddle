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

# Paths
TAP_REPO := $(HOME)/Developer/tools/ansilithic/homebrew-tap
FORMULA := $(TAP_REPO)/Formula/saddle.rb
SOURCE := Sources/saddle/Saddle.swift

.DEFAULT_GOAL := help
.PHONY: build install uninstall clean rebuild release test help

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
	@rm -f $(BIN_DIR)/$(BINARY)
	@cp .build/release/$(BINARY) $(BIN_DIR)/$(BINARY)
	@echo "$(GREEN)Installed!$(RESET) Run 'saddle status' to check your repos."

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
# Release (bump version, tag, push, update tap)
# Usage: make release V=1.1.0
# ============================================================
release:
	@if [ -z "$(V)" ]; then \
		echo "$(YELLOW)Usage:$(RESET) make release V=x.y.z"; \
		echo "  Current version: $$(grep 'version:' $(SOURCE) | head -1 | sed 's/.*"\(.*\)".*/\1/')"; \
		exit 1; \
	fi
	@CURRENT=$$(grep 'version:' $(SOURCE) | head -1 | sed 's/.*"\(.*\)".*/\1/'); \
	if [ "$$CURRENT" = "$(V)" ]; then \
		echo "$(YELLOW)Version is already $(V).$(RESET)"; \
		exit 1; \
	fi; \
	echo "$(BOLD)Releasing $(BINARY) v$(V)$(RESET) (was $$CURRENT)"; \
	echo ""; \
	echo "$(CYAN)1/5$(RESET) Bumping version in source..."; \
	sed -i '' 's/version: ".*"/version: "$(V)"/' $(SOURCE); \
	echo "$(CYAN)2/5$(RESET) Building to verify..."; \
	swift build -c release || exit 1; \
	echo "$(CYAN)3/5$(RESET) Committing and tagging..."; \
	git add $(SOURCE) && git commit -m "Bump version to $(V)"; \
	git tag "v$(V)"; \
	git push origin main && git push origin "v$(V)"; \
	echo "$(CYAN)4/5$(RESET) Creating GitHub release..."; \
	gh release create "v$(V)" --title "v$(V)" --generate-notes; \
	echo "$(CYAN)5/5$(RESET) Updating Homebrew tap..."; \
	SHA=$$(curl -sL "https://github.com/ansilithic/saddle/archive/refs/tags/v$(V).tar.gz" | shasum -a 256 | cut -d' ' -f1); \
	sed -i '' 's|archive/refs/tags/v.*\.tar\.gz|archive/refs/tags/v$(V).tar.gz|' $(FORMULA); \
	sed -i '' 's/sha256 ".*"/sha256 "'$$SHA'"/' $(FORMULA); \
	cd $(TAP_REPO) && git add Formula/saddle.rb && git commit -m "Update saddle to $(V)" && git push origin main; \
	echo ""; \
	echo "$(GREEN)Released $(BINARY) v$(V)!$(RESET)"; \
	echo "  brew update && brew upgrade saddle"

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
	@echo "  $(CYAN)release$(RESET)   $(GRAY)-$(RESET) $(GREEN)Tag, release, and update Homebrew tap$(RESET)"
	@echo "  $(CYAN)uninstall$(RESET) $(GRAY)-$(RESET) $(GREEN)Remove binary from /usr/local/bin$(RESET)"
	@echo "  $(CYAN)test$(RESET)      $(GRAY)-$(RESET) $(GREEN)Run tests$(RESET)"
	@echo "  $(CYAN)clean$(RESET)     $(GRAY)-$(RESET) $(GREEN)Remove build artifacts$(RESET)"
	@echo "  $(CYAN)help$(RESET)      $(GRAY)-$(RESET) $(GREEN)Show this help message (default)$(RESET)"
	@echo ""
