#!/bin/bash
# Cached Test Runner - Integrates caching with test execution
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

# Initialize cache system
initialize_cache() {
    ./test-cache-manager.sh init >/dev/null 2>&1 || true
}

# Cached build function
cached_build() {
    echo -e "${BLUE}🔨 Building with cache optimization${NC}"

    # Check if build cache is valid
    if ./test-cache-manager.sh build-check 2>/dev/null; then
        echo -e "${GREEN}⚡ Restoring build from cache${NC}"
        if ./test-cache-manager.sh build-restore; then
            return 0
        fi
    fi

    # Build is needed
    echo -e "${YELLOW}🔄 Cache miss - building from source${NC}"
    local start_time=$(date +%s.%3N)

    if forge build; then
        local end_time=$(date +%s.%3N)
        local duration=$(echo "$end_time - $start_time" | bc -l)
        echo -e "${GREEN}✅ Build completed in ${duration}s${NC}"

        # Update build cache
        ./test-cache-manager.sh build-update
        return 0
    else
        echo -e "${RED}❌ Build failed${NC}"
        return 1
    fi
}

# Cached test execution
cached_test() {
    local test_type="${1:-forge}"
    local test_command="${2:-forge test}"
    local force_run="${3:-false}"

    echo -e "${BLUE}🧪 Running $test_type tests with cache optimization${NC}"

    # Check if test cache is valid (unless forced)
    if [[ "$force_run" != "true" ]] && ./test-cache-manager.sh test-check "$test_type" 2>/dev/null; then
        echo -e "${GREEN}⚡ Using cached test results for $test_type${NC}"
        ./test-cache-manager.sh test-get "$test_type"
        return $?
    fi

    # Test cache miss - run tests
    echo -e "${YELLOW}🔄 Cache miss - running $test_type tests${NC}"
    local start_time=$(date +%s.%3N)
    local output_file=$(mktemp)

    # Run the test command
    local exit_code=0
    eval "$test_command" | tee "$output_file" || exit_code=$?

    local end_time=$(date +%s.%3N)
    local duration=$(echo "$end_time - $start_time" | bc -l)

    # Update test cache
    local output_content=$(cat "$output_file")
    ./test-cache-manager.sh test-update "$test_type" "$exit_code" "$output_content"

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✅ $test_type tests completed in ${duration}s${NC}"
    else
        echo -e "${RED}❌ $test_type tests failed after ${duration}s${NC}"
    fi

    rm -f "$output_file"
    return $exit_code
}

# Cached Echidna execution with corpus management
cached_echidna() {
    local contract="${1:-SimpleTest}"
    local contract_file="${2:-test/echidna/SimpleTest.sol}"
    local environment="${3:-$(detect_environment)}"

    echo -e "${BLUE}🔍 Running Echidna tests with corpus caching${NC}"

    # Initialize Echidna corpus cache for environment
    ./test-cache-manager.sh echidna-corpus init "$environment"
    local corpus_dir=$(./test-cache-manager.sh echidna-corpus path "$environment")

    # Configure environment
    configure_environment

    # Prepare Echidna command with corpus caching
    local config_file
    case "$environment" in
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

    # Update config to use cached corpus
    if [[ -f "$config_file" ]]; then
        # Create temp config with corpus directory
        local temp_config=$(mktemp)
        cp "$config_file" "$temp_config"
        echo "corpusDir: \"$corpus_dir\"" >> "$temp_config"
        config_file="$temp_config"
    fi

    # Check if we can use cached results
    local cache_valid=false
    if ./test-cache-manager.sh test-check "echidna_${environment}" 2>/dev/null; then
        cache_valid=true
    fi

    if [[ "$cache_valid" == "true" ]]; then
        echo -e "${GREEN}⚡ Using cached Echidna results${NC}"
        ./test-cache-manager.sh test-get "echidna_${environment}"
        local result=$?
        [[ -f "$temp_config" ]] && rm -f "$temp_config"
        return $result
    fi

    # Run Echidna with caching
    echo -e "${YELLOW}🔄 Running Echidna with corpus caching${NC}"
    export PATH="/home/justin/.local/bin:$PATH"

    local start_time=$(date +%s.%3N)
    local output_file=$(mktemp)
    local exit_code=0

    local cmd="timeout $TEST_TIMEOUT echidna \"$contract_file\" --contract \"$contract\""
    if [[ -f "$config_file" ]]; then
        cmd="$cmd --config \"$config_file\""
    fi

    eval "$cmd" | tee "$output_file" || exit_code=$?

    local end_time=$(date +%s.%3N)
    local duration=$(echo "$end_time - $start_time" | bc -l)

    # Update cache
    local output_content=$(cat "$output_file")
    ./test-cache-manager.sh test-update "echidna_${environment}" "$exit_code" "$output_content"

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✅ Echidna tests completed in ${duration}s${NC}"
    else
        echo -e "${YELLOW}⚠️  Echidna tests completed with warnings after ${duration}s${NC}"
    fi

    # Cleanup
    rm -f "$output_file"
    [[ -f "$temp_config" ]] && rm -f "$temp_config"

    return $exit_code
}

# Cached Scribble execution
cached_scribble() {
    local action="${1:-check}"

    echo -e "${BLUE}📋 Running Scribble tests with caching${NC}"

    # Initialize Scribble cache
    ./test-cache-manager.sh scribble init

    case "$action" in
        "check")
            cached_test "scribble_check" "npx scribble --check src/ScribbleValidationContract.sol"
            ;;
        "instrument")
            cached_test "scribble_instrument" "npx scribble --output-mode files src/ScribbleValidationContract.sol"
            ;;
        "full")
            cached_scribble "check"
            cached_scribble "instrument"
            ;;
        *)
            echo -e "${RED}❌ Unknown Scribble action: $action${NC}"
            return 1
            ;;
    esac
}

# Main cached test execution
run_cached_tests() {
    local test_type="${1:-all}"
    local force="${2:-false}"

    # Initialize cache system
    initialize_cache

    # Configure environment
    configure_environment

    echo -e "${BLUE}🚀 Cached Test Runner (environment: $FOUNDRY_PROFILE)${NC}"
    echo "=================================================="

    case "$test_type" in
        "build")
            cached_build
            ;;
        "forge")
            cached_build && cached_test "forge" "forge test --no-gas-report" "$force"
            ;;
        "fuzz")
            cached_build && cached_test "fuzz" "forge test --match-test fuzz" "$force"
            ;;
        "echidna")
            cached_echidna
            ;;
        "scribble")
            cached_scribble "full"
            ;;
        "quick")
            echo -e "${BLUE}🏃 Running quick cached tests${NC}"
            cached_build && cached_test "forge_quick" "forge test --no-gas-report" "$force"
            ;;
        "security")
            echo -e "${BLUE}🔒 Running security test suite with caching${NC}"
            cached_build
            cached_echidna
            cached_scribble "full"
            ;;
        "all")
            echo -e "${BLUE}🎯 Running comprehensive cached test suite${NC}"
            cached_build
            cached_test "forge" "forge test" "$force"
            cached_test "fuzz" "forge test --match-test fuzz" "$force"
            cached_echidna
            cached_scribble "full"
            ;;
        *)
            echo -e "${RED}❌ Unknown test type: $test_type${NC}"
            echo "Available types: build, forge, fuzz, echidna, scribble, quick, security, all"
            return 1
            ;;
    esac
}

# Show cache statistics
show_cache_stats() {
    echo -e "${BLUE}📊 Cache Performance Statistics${NC}"
    echo "==============================="

    ./test-cache-manager.sh status
}

# Clean cache with confirmation
clean_cache_interactive() {
    local cache_type="${1:-all}"

    echo -e "${YELLOW}⚠️  This will clean the $cache_type cache${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ./test-cache-manager.sh clean "$cache_type"
    else
        echo "Cache clean cancelled"
    fi
}

# Show help
show_help() {
    echo "Cached Test Runner - Performance-optimized testing with intelligent caching"
    echo ""
    echo "Usage:"
    echo "  $0 [test_type] [options]"
    echo ""
    echo "Test Types:"
    echo "  build       - Build with caching"
    echo "  forge       - Run Forge tests with caching"
    echo "  fuzz        - Run fuzz tests with caching"
    echo "  echidna     - Run Echidna tests with corpus caching"
    echo "  scribble    - Run Scribble tests with caching"
    echo "  quick       - Run quick tests with caching"
    echo "  security    - Run security test suite with caching"
    echo "  all         - Run comprehensive test suite with caching (default)"
    echo ""
    echo "Cache Management:"
    echo "  stats       - Show cache statistics"
    echo "  clean [type] - Clean cache (with confirmation)"
    echo "  force <type> - Force run tests (bypass cache)"
    echo ""
    echo "Environment Variables:"
    echo "  FOUNDRY_PROFILE - Override environment detection"
    echo "  CI              - Set to 'true' for CI mode"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run all tests with caching"
    echo "  $0 forge              # Run Forge tests with caching"
    echo "  $0 force fuzz         # Force run fuzz tests (bypass cache)"
    echo "  $0 stats              # Show cache statistics"
    echo "  $0 clean build        # Clean build cache"
}

# Main execution
main() {
    local command="${1:-all}"
    local option="${2:-}"

    case "$command" in
        "force")
            local test_type="${2:-all}"
            run_cached_tests "$test_type" "true"
            ;;
        "stats")
            show_cache_stats
            ;;
        "clean")
            clean_cache_interactive "$option"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            run_cached_tests "$command" "$option"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
