#!/bin/bash
# Adaptive Test Runner - Automatically adjusts test intensity based on environment
# Part of Story 024.53 - Performance Optimization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-environment.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configure environment
configure_environment

echo -e "${BLUE}🚀 Adaptive Test Runner${NC}"
echo "=========================="

# Function to run tests with environment-specific configuration
run_forge_tests() {
    local test_pattern="${1:-}"
    local extra_args="${2:-}"

    echo -e "${YELLOW}🧪 Running Forge tests (profile: $FOUNDRY_PROFILE)${NC}"

    local cmd="forge test"
    if [[ -n "$test_pattern" ]]; then
        cmd="$cmd --match-test \"$test_pattern\""
    fi

    if [[ -n "$extra_args" ]]; then
        cmd="$cmd $extra_args"
    fi

    echo "Command: $cmd"
    eval "$cmd"
}

# Function to run Echidna tests with environment-specific configuration
run_echidna_tests() {
    local contract="${1:-SimpleTest}"
    local contract_file="${2:-test/echidna/SimpleTest.sol}"

    echo -e "${YELLOW}🔍 Running Echidna tests (limit: $TEST_ECHIDNA_LIMIT)${NC}"

    if ! command -v echidna >/dev/null 2>&1; then
        echo -e "${RED}❌ Echidna not found. Please install Echidna.${NC}"
        return 1
    fi

    export PATH="/home/justin/.local/bin:$PATH"

    local config_file
    case "$FOUNDRY_PROFILE" in
        "ci")
            config_file="echidna-ci.yaml"
            ;;
        "local"|"extended")
            config_file="echidna-local.yaml"
            ;;
        *)
            config_file="echidna.yaml"
            ;;
    esac

    local cmd="timeout $TEST_TIMEOUT echidna \"$contract_file\" --contract \"$contract\""

    if [[ -f "$config_file" ]]; then
        cmd="$cmd --config \"$config_file\""
    else
        cmd="$cmd --test-limit $TEST_ECHIDNA_LIMIT"
    fi

    echo "Command: $cmd"
    eval "$cmd"
}

# Function to run Scribble tests
run_scribble_tests() {
    echo -e "${YELLOW}📋 Running Scribble tests${NC}"

    if ! command -v npx >/dev/null 2>&1; then
        echo -e "${RED}❌ npm/npx not found. Please install Node.js and npm.${NC}"
        return 1
    fi

    # Quick Scribble check
    echo "Running Scribble validation..."
    timeout $TEST_TIMEOUT npx scribble --check src/ScribbleValidationContract.sol 2>/dev/null || echo "Warning: Scribble check completed with warnings"

    # Instrumentation (local/extended environments only)
    if [[ "$FOUNDRY_PROFILE" != "ci" && "$FOUNDRY_PROFILE" != "quick" ]]; then
        echo "Running Scribble instrumentation..."
        mkdir -p scribble-output
        timeout $TEST_TIMEOUT npx scribble --output-mode files src/ScribbleValidationContract.sol > scribble-output/adaptive-run-$(date +%Y%m%d_%H%M%S).log 2>&1 || echo "Warning: Scribble instrumentation completed with warnings"
    fi
}

# Function to run static analysis
run_static_analysis() {
    echo -e "${YELLOW}🔒 Running static analysis${NC}"

    # Solhint (always run)
    if command -v npx >/dev/null 2>&1; then
        echo "Running Solhint..."
        npx solhint 'src/**/*.sol' 'test/**/*.sol' || echo "Warning: Solhint completed with warnings"
    fi

    # Slither (skip in quick mode)
    if [[ "$FOUNDRY_PROFILE" != "quick" ]] && command -v slither >/dev/null 2>&1; then
        echo "Running Slither..."
        timeout $TEST_TIMEOUT slither . --exclude-dependencies --disable-color --filter-paths "test/,lib/" || echo "Warning: Slither completed with warnings"
    fi
}

# Main test execution function
run_adaptive_tests() {
    local test_type="${1:-all}"
    local start_time=$(date +%s)

    mkdir -p docs/reports cache

    echo -e "${BLUE}📊 Test Configuration Summary:${NC}"
    echo "  Environment: $FOUNDRY_PROFILE"
    echo "  Fuzz runs: $TEST_FUZZ_RUNS"
    echo "  Echidna limit: $TEST_ECHIDNA_LIMIT"
    echo "  Timeout: ${TEST_TIMEOUT}s"
    echo ""

    case "$test_type" in
        "forge"|"fuzz")
            run_forge_tests "fuzz"
            ;;
        "echidna"|"property")
            run_echidna_tests
            ;;
        "scribble")
            run_scribble_tests
            ;;
        "static")
            run_static_analysis
            ;;
        "core")
            echo -e "${BLUE}🏗️  Running core test suite${NC}"
            forge build
            run_forge_tests "" "--no-gas-report"
            ;;
        "security")
            echo -e "${BLUE}🔒 Running security test suite${NC}"
            run_echidna_tests
            run_scribble_tests
            run_static_analysis
            ;;
        "all")
            echo -e "${BLUE}🎯 Running comprehensive test suite${NC}"
            echo "Building contracts..."
            forge build

            echo "Running core tests..."
            run_forge_tests

            echo "Running fuzz tests..."
            run_forge_tests "fuzz"

            echo "Running property-based tests..."
            run_echidna_tests

            echo "Running specification tests..."
            run_scribble_tests

            echo "Running static analysis..."
            run_static_analysis
            ;;
        *)
            echo -e "${RED}❌ Unknown test type: $test_type${NC}"
            echo "Available types: forge, fuzz, echidna, property, scribble, static, core, security, all"
            exit 1
            ;;
    esac

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    echo -e "${GREEN}✅ Adaptive testing complete!${NC}"
    echo "Total duration: ${duration}s"
    echo "Environment: $FOUNDRY_PROFILE"
}

# Function to show help
show_help() {
    echo "Adaptive Test Runner - Environment-aware testing"
    echo ""
    echo "Usage:"
    echo "  $0 [test_type] [options]"
    echo ""
    echo "Test Types:"
    echo "  all         - Run comprehensive test suite (default)"
    echo "  core        - Run core Forge tests only"
    echo "  forge       - Run Forge tests"
    echo "  fuzz        - Run fuzz tests"
    echo "  echidna     - Run Echidna property tests"
    echo "  property    - Alias for echidna"
    echo "  scribble    - Run Scribble specification tests"
    echo "  static      - Run static analysis tools"
    echo "  security    - Run security-focused tests (echidna + scribble + static)"
    echo ""
    echo "Environment Variables:"
    echo "  FOUNDRY_PROFILE - Override detected environment (ci, local, extended, quick)"
    echo "  CI              - Set to 'true' to force CI mode"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run all tests with auto-detected environment"
    echo "  $0 fuzz               # Run only fuzz tests"
    echo "  FOUNDRY_PROFILE=quick $0 core  # Run core tests in quick mode"
    echo "  CI=true $0 security   # Run security tests in CI mode"
}

# Main execution
main() {
    local test_type="${1:-all}"

    case "$test_type" in
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            run_adaptive_tests "$test_type"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
