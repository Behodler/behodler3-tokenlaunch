#!/bin/bash
# Test Environment Detection and Configuration Script
# Part of Story 024.53 - Performance Optimization

set -euo pipefail

# Detect environment type
detect_environment() {
    if [[ "${CI:-false}" == "true" ]]; then
        echo "ci"
    elif [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
        echo "ci"
    elif [[ -n "${FOUNDRY_PROFILE:-}" ]]; then
        echo "$FOUNDRY_PROFILE"
    else
        echo "local"
    fi
}

# Get test configuration based on environment
get_test_config() {
    local env_type="$1"
    local test_type="${2:-fuzz}"

    case "$env_type" in
        "ci")
            case "$test_type" in
                "fuzz")
                    echo "256"  # Fuzz runs for CI
                    ;;
                "echidna")
                    echo "50"   # Echidna test limit for CI
                    ;;
                "invariant")
                    echo "32"   # Invariant runs for CI
                    ;;
                "timeout")
                    echo "60"   # Max timeout for CI tests
                    ;;
                *)
                    echo "ci"
                    ;;
            esac
            ;;
        "local")
            case "$test_type" in
                "fuzz")
                    echo "10000"  # Fuzz runs for local
                    ;;
                "echidna")
                    echo "1000"  # Echidna test limit for local
                    ;;
                "invariant")
                    echo "256"   # Invariant runs for local
                    ;;
                "timeout")
                    echo "300"   # Max timeout for local tests
                    ;;
                *)
                    echo "local"
                    ;;
            esac
            ;;
        "extended")
            case "$test_type" in
                "fuzz")
                    echo "50000"  # Fuzz runs for extended
                    ;;
                "echidna")
                    echo "5000"  # Echidna test limit for extended
                    ;;
                "invariant")
                    echo "1000"  # Invariant runs for extended
                    ;;
                "timeout")
                    echo "600"   # Max timeout for extended tests
                    ;;
                *)
                    echo "extended"
                    ;;
            esac
            ;;
        "quick")
            case "$test_type" in
                "fuzz")
                    echo "100"   # Fuzz runs for quick
                    ;;
                "echidna")
                    echo "20"    # Echidna test limit for quick
                    ;;
                "invariant")
                    echo "10"    # Invariant runs for quick
                    ;;
                "timeout")
                    echo "30"    # Max timeout for quick tests
                    ;;
                *)
                    echo "quick"
                    ;;
            esac
            ;;
        *)
            echo "local"  # Default to local
            ;;
    esac
}

# Export environment variables based on detected environment
configure_environment() {
    local env_type=$(detect_environment)

    echo "🔍 Detected environment: $env_type"

    # Set Foundry profile
    export FOUNDRY_PROFILE="$env_type"

    # Set test configuration variables
    export TEST_FUZZ_RUNS=$(get_test_config "$env_type" "fuzz")
    export TEST_ECHIDNA_LIMIT=$(get_test_config "$env_type" "echidna")
    export TEST_INVARIANT_RUNS=$(get_test_config "$env_type" "invariant")
    export TEST_TIMEOUT=$(get_test_config "$env_type" "timeout")

    # Set cache directory
    export TEST_CACHE_DIR="cache/$env_type"
    mkdir -p "$TEST_CACHE_DIR"

    echo "📊 Test Configuration:"
    echo "  - Profile: $FOUNDRY_PROFILE"
    echo "  - Fuzz runs: $TEST_FUZZ_RUNS"
    echo "  - Echidna limit: $TEST_ECHIDNA_LIMIT"
    echo "  - Invariant runs: $TEST_INVARIANT_RUNS"
    echo "  - Timeout: ${TEST_TIMEOUT}s"
    echo "  - Cache dir: $TEST_CACHE_DIR"
}

# Main execution
main() {
    local command="${1:-configure}"

    case "$command" in
        "detect")
            detect_environment
            ;;
        "configure")
            configure_environment
            ;;
        "get")
            local env_type="${2:-$(detect_environment)}"
            local test_type="${3:-fuzz}"
            get_test_config "$env_type" "$test_type"
            ;;
        "help")
            echo "Test Environment Configuration Script"
            echo ""
            echo "Usage:"
            echo "  $0 detect           - Detect current environment"
            echo "  $0 configure        - Configure environment variables"
            echo "  $0 get <env> <type> - Get specific configuration value"
            echo "  $0 help             - Show this help"
            echo ""
            echo "Environments: ci, local, extended, quick"
            echo "Types: fuzz, echidna, invariant, timeout"
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
