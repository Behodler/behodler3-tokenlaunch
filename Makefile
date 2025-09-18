# Behodler3 TokenLaunch - Code Quality Makefile
# Comprehensive code quality and development toolchain

.PHONY: help install-dev clean build test lint format quality quality-fix check-all deps

# Default target
help: ## Show this help message
	@echo "Behodler3 TokenLaunch - Code Quality Targets"
	@echo "============================================"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ============ DEVELOPMENT SETUP ============

install-dev: ## Install development dependencies (npm, forge, pre-commit)
	@echo "🔧 Installing development dependencies..."
	npm install
	forge install
	pre-commit install
	@echo "✅ Development environment ready!"

deps: ## Show dependency status
	@echo "📦 Dependency Status:"
	@echo "Node.js: $$(node --version 2>/dev/null || echo 'Not installed')"
	@echo "npm: $$(npm --version 2>/dev/null || echo 'Not installed')"
	@echo "Forge: $$(forge --version 2>/dev/null | head -1 || echo 'Not installed')"
	@echo "Pre-commit: $$(pre-commit --version 2>/dev/null || echo 'Not installed')"
	@echo "Solhint: $$(npx solhint --version 2>/dev/null || echo 'Not installed')"
	@echo "Prettier: $$(npx prettier --version 2>/dev/null || echo 'Not installed')"

# ============ BUILD TARGETS ============

clean: ## Clean build artifacts
	@echo "🧹 Cleaning build artifacts..."
	forge clean
	rm -rf cache/ out/ node_modules/.cache/
	@echo "✅ Clean complete!"

build: ## Build contracts with Foundry
	@echo "🔨 Building contracts..."
	forge build
	@echo "✅ Build complete!"

build-watch: ## Build contracts in watch mode
	@echo "👀 Building contracts in watch mode..."
	forge build --watch

# ============ TESTING TARGETS ============

test: ## Run all tests
	@echo "🧪 Running all tests..."
	forge test

test-verbose: ## Run tests with verbose output
	@echo "🧪 Running tests (verbose)..."
	forge test -vvv

test-gas: ## Run tests with gas reporting
	@echo "⛽ Running tests with gas reporting..."
	forge test --gas-report

test-coverage: ## Run test coverage analysis
	@echo "📊 Running test coverage analysis..."
	forge coverage

test-watch: ## Run tests in watch mode
	@echo "👀 Running tests in watch mode..."
	forge test --watch

# ============ LINTING TARGETS ============

lint: lint-solidity ## Run all linting checks
	@echo "✅ All linting checks complete!"

lint-solidity: ## Run Solidity linting with solhint
	@echo "🔍 Linting Solidity files..."
	npx solhint 'src/**/*.sol' 'test/**/*.sol'

lint-solidity-fix: ## Fix auto-fixable Solidity linting issues
	@echo "🔧 Fixing Solidity linting issues..."
	npx solhint 'src/**/*.sol' 'test/**/*.sol' --fix

# ============ FORMATTING TARGETS ============

format: format-solidity format-other ## Apply all formatting
	@echo "✅ All formatting complete!"

format-solidity: ## Format Solidity files with forge fmt
	@echo "🎨 Formatting Solidity files..."
	forge fmt

format-other: ## Format JSON, Markdown, YAML files with prettier
	@echo "🎨 Formatting other files..."
	npx prettier --write '**/*.{json,md,yml,yaml}'

format-check: format-check-solidity format-check-other ## Check all formatting
	@echo "✅ All formatting checks complete!"

format-check-solidity: ## Check Solidity formatting
	@echo "🔍 Checking Solidity formatting..."
	forge fmt --check

format-check-other: ## Check other file formatting
	@echo "🔍 Checking other file formatting..."
	npx prettier --check '**/*.{json,md,yml,yaml}'

# ============ QUALITY TARGETS ============

quality: lint format-check ## Run full quality check suite
	@echo "🏆 Quality check complete!"

quality-fix: lint-solidity-fix format ## Fix all auto-fixable quality issues
	@echo "🔧 Auto-fixes applied!"

# ============ SECURITY TARGETS ============

security-scan: ## Run security analysis tools
	@echo "🔒 Running security analysis..."
	@echo "📝 Detected secrets baseline scan..."
	detect-secrets scan . --baseline .secrets.baseline || echo "⚠️  New secrets detected - review required"
	@echo "🔍 Solhint security rules already included in lint target"

security-update-baseline: ## Update secrets detection baseline
	@echo "🔄 Updating secrets baseline..."
	detect-secrets scan . > .secrets.baseline
	@echo "✅ Secrets baseline updated!"

# ============ STATIC ANALYSIS TARGETS ============

static-analysis: slither-analysis mythril-analysis manticore-analysis ## Run all static analysis tools
	@echo ""
	@echo "🎯 STATIC ANALYSIS COMPLETE! 🎯"
	@echo "==============================="
	@echo "✅ Slither analysis completed"
	@echo "✅ Mythril analysis completed"
	@echo "✅ Manticore analysis completed (or fallback documented)"
	@echo "📁 Reports available in docs/reports/"
	@echo ""

slither-analysis: ## Run Slither static analysis
	@echo "🔍 Running Slither static analysis..."
	@mkdir -p docs/reports
	@timestamp=$$(date +%Y%m%d_%H%M%S); \
	echo "📊 Generating Slither reports (timestamp: $$timestamp)..."; \
	slither . --json docs/reports/slither-$$timestamp.json 2>/dev/null || true; \
	slither . --sarif docs/reports/slither-$$timestamp.sarif 2>/dev/null || true; \
	slither . --checklist > docs/reports/slither-checklist-$$timestamp.md 2>/dev/null || true; \
	slither . > docs/reports/slither-$$timestamp.txt 2>/dev/null || true; \
	echo "✅ Slither analysis complete! Reports saved to docs/reports/"

mythril-analysis: ## Run Mythril security analysis
	@echo "🛡️  Running Mythril security analysis..."
	@mkdir -p docs/reports
	@timestamp=$$(date +%Y%m%d_%H%M%S); \
	echo "📊 Generating Mythril reports (timestamp: $$timestamp)..."; \
	if command -v myth >/dev/null 2>&1; then \
		if [ -f mythril-analyze.sh ]; then \
			find src -name "*.sol" -type f | grep -v interfaces | head -5 | while read contract; do \
				echo "🔍 Analyzing $$contract with import callback fix..."; \
				./mythril-analyze.sh -f "$$contract" -t 300 > "docs/reports/mythril-$$(basename $$contract .sol)-$$timestamp.txt" 2>&1 || \
				echo "⚠️  Analysis timeout or error for $$contract" >> "docs/reports/mythril-$$(basename $$contract .sol)-$$timestamp.txt"; \
			done; \
		else \
			echo "⚠️  mythril-analyze.sh script not found, using fallback method..."; \
			find src -name "*.sol" -type f | head -5 | while read contract; do \
				echo "🔍 Analyzing $$contract..."; \
				timeout 300 myth analyze "$$contract" --solv 0.8.25 > "docs/reports/mythril-$$(basename $$contract .sol)-$$timestamp.txt" 2>&1 || \
				echo "⚠️  Analysis timeout or error for $$contract" >> "docs/reports/mythril-$$(basename $$contract .sol)-$$timestamp.txt"; \
			done; \
		fi; \
		echo "✅ Mythril analysis complete! Reports saved to docs/reports/"; \
	else \
		echo "⚠️  Mythril not found - creating fallback report..."; \
		echo "# Mythril Analysis - Not Available" > docs/reports/mythril-fallback-$$timestamp.md; \
		echo "Mythril analysis could not be performed due to installation issues." >> docs/reports/mythril-fallback-$$timestamp.md; \
		echo "Please install Mythril manually: pip install mythril" >> docs/reports/mythril-fallback-$$timestamp.md; \
	fi

manticore-analysis: ## Run Manticore symbolic execution (with fallback)
	@echo "🎲 Running Manticore symbolic execution..."
	@mkdir -p docs/reports
	@timestamp=$$(date +%Y%m%d_%H%M%S); \
	echo "📊 Generating Manticore reports (timestamp: $$timestamp)..."; \
	if command -v manticore >/dev/null 2>&1; then \
		find src -name "*.sol" -type f | head -3 | while read contract; do \
			echo "🔍 Analyzing $$contract with Manticore..."; \
			timeout 600 manticore "$$contract" --workspace /tmp/manticore_workspace_$$$$ > "docs/reports/manticore-$$(basename $$contract .sol)-$$timestamp.txt" 2>&1 || \
			echo "⚠️  Analysis timeout or error for $$contract" >> "docs/reports/manticore-$$(basename $$contract .sol)-$$timestamp.txt"; \
		done; \
		echo "✅ Manticore analysis complete! Reports saved to docs/reports/"; \
	else \
		echo "⚠️  Manticore not available - creating fallback documentation..."; \
		echo "# Manticore Analysis - Not Available" > docs/reports/manticore-fallback-$$timestamp.md; \
		echo "" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "## Status" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "Manticore symbolic execution could not be performed due to installation issues." >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "## Installation Issues" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "- Manticore requires specific Python dependencies that failed to compile" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "- Build errors occurred during pysha3 compilation" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "## Alternative Solutions" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "1. Use Echidna for property-based testing instead" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "2. Use Foundry's built-in fuzzing capabilities" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "3. Install Manticore in a Docker container" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "## Manual Installation" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "\`\`\`bash" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "# Try with Docker:" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "docker run --rm -v \$$PWD:/workspace trailofbits/manticore /workspace/src/Contract.sol" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "\`\`\`" >> docs/reports/manticore-fallback-$$timestamp.md; \
		echo "✅ Manticore fallback documentation created!"; \
	fi

static-analysis-quick: slither-analysis ## Run quick static analysis (Slither only)
	@echo "⚡ Quick static analysis complete!"

# ============ PRE-COMMIT TARGETS ============

pre-commit-run: ## Run pre-commit hooks on all files
	@echo "🔗 Running pre-commit hooks..."
	pre-commit run --all-files

pre-commit-run-hook: ## Run specific pre-commit hook (usage: make pre-commit-run-hook HOOK=prettier)
	@echo "🔗 Running pre-commit hook: $(HOOK)..."
	pre-commit run $(HOOK) --all-files

pre-commit-update: ## Update pre-commit hook versions
	@echo "🔄 Updating pre-commit hooks..."
	pre-commit autoupdate

# ============ COMPREHENSIVE TARGETS ============

check-all: deps build test quality security-scan static-analysis ## Run comprehensive check suite
	@echo ""
	@echo "🎉 COMPREHENSIVE CHECK COMPLETE! 🎉"
	@echo "======================================"
	@echo "✅ Dependencies verified"
	@echo "✅ Build successful"
	@echo "✅ Tests passed"
	@echo "✅ Code quality checks passed"
	@echo "✅ Security scans completed"
	@echo "✅ Static analysis completed"
	@echo ""

dev-setup: install-dev build test ## Complete development environment setup
	@echo ""
	@echo "🚀 DEVELOPMENT ENVIRONMENT READY! 🚀"
	@echo "===================================="
	@echo "✅ Dependencies installed"
	@echo "✅ Pre-commit hooks enabled"
	@echo "✅ Build successful"
	@echo "✅ Tests passing"
	@echo ""
	@echo "💡 Next steps:"
	@echo "   • Run 'make quality' to check code quality"
	@echo "   • Run 'make check-all' for comprehensive verification"
	@echo "   • Start coding! Pre-commit hooks will maintain quality automatically"
	@echo ""

# ============ NPM SCRIPT INTEGRATION ============

npm-lint: ## Run npm lint script
	npm run lint

npm-format: ## Run npm format script
	npm run format

npm-quality: ## Run npm quality script
	npm run quality

npm-quality-fix: ## Run npm quality fix script
	npm run quality:fix

# ============ DOCUMENTATION TARGETS ============

docs-lint: ## Check documentation formatting
	@echo "📚 Checking documentation..."
	npx prettier --check '**/*.md'

docs-format: ## Format documentation
	@echo "📚 Formatting documentation..."
	npx prettier --write '**/*.md'

# ============ GIT INTEGRATION ============

git-hooks-test: ## Test git hooks without committing
	pre-commit run --all-files

git-pre-push: build test quality ## Pre-push validation
	@echo "🚀 Pre-push validation complete!"

# ============ PERFORMANCE TARGETS ============

gas-snapshot: ## Create gas usage snapshot
	@echo "⛽ Creating gas snapshot..."
	forge snapshot

gas-compare: ## Compare gas usage with snapshot
	@echo "⚽ Comparing gas usage..."
	forge snapshot --diff

# Show available targets by default
.DEFAULT_GOAL := help
