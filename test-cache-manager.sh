#!/bin/bash
# Test Cache Manager - Intelligent caching for test execution optimization
# Part of Story 024.53 - Performance Optimization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/cache"
BUILD_CACHE_DIR="$CACHE_DIR/build"
TEST_CACHE_DIR="$CACHE_DIR/test"
ECHIDNA_CACHE_DIR="$CACHE_DIR/echidna"
SCRIBBLE_CACHE_DIR="$CACHE_DIR/scribble"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize cache directories
init_cache() {
    echo -e "${BLUE}🔧 Initializing test cache system${NC}"

    mkdir -p "$BUILD_CACHE_DIR"
    mkdir -p "$TEST_CACHE_DIR"
    mkdir -p "$ECHIDNA_CACHE_DIR"
    mkdir -p "$SCRIBBLE_CACHE_DIR"

    # Create cache metadata
    echo "$(date -Iseconds)" > "$CACHE_DIR/initialized"
    echo "# Test Cache Directory - Generated automatically" > "$CACHE_DIR/README.md"

    echo -e "${GREEN}✅ Cache system initialized${NC}"
}

# Calculate hash of source files for cache invalidation
calculate_source_hash() {
    local target_dir="${1:-src}"

    if [[ ! -d "$target_dir" ]]; then
        echo "no-source"
        return
    fi

    find "$target_dir" -name "*.sol" -type f -exec sha256sum {} \; | \
    sort | sha256sum | cut -d' ' -f1
}

# Calculate hash of test files for cache invalidation
calculate_test_hash() {
    local target_dir="${1:-test}"

    if [[ ! -d "$target_dir" ]]; then
        echo "no-tests"
        return
    fi

    find "$target_dir" -name "*.sol" -type f -exec sha256sum {} \; | \
    sort | sha256sum | cut -d' ' -f1
}

# Calculate configuration hash for cache invalidation
calculate_config_hash() {
    local config_files=("foundry.toml" "echidna.yaml" "echidna-ci.yaml" "echidna-local.yaml" ".solhint.json")
    local combined_hash=""

    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            combined_hash="${combined_hash}$(sha256sum "$file" | cut -d' ' -f1)"
        fi
    done

    echo -n "$combined_hash" | sha256sum | cut -d' ' -f1
}

# Check if build cache is valid
is_build_cache_valid() {
    local current_hash=$(calculate_source_hash)
    local cache_file="$BUILD_CACHE_DIR/source_hash"

    if [[ -f "$cache_file" ]] && [[ -d "out" ]]; then
        local cached_hash=$(cat "$cache_file")
        [[ "$current_hash" == "$cached_hash" ]]
    else
        false
    fi
}

# Update build cache
update_build_cache() {
    local current_hash=$(calculate_source_hash)
    echo "$current_hash" > "$BUILD_CACHE_DIR/source_hash"
    echo "$(date -Iseconds)" > "$BUILD_CACHE_DIR/last_build"

    # Copy build artifacts to cache
    if [[ -d "out" ]]; then
        cp -r out "$BUILD_CACHE_DIR/" 2>/dev/null || true
    fi

    echo -e "${GREEN}📦 Build cache updated${NC}"
}

# Restore build from cache
restore_build_cache() {
    if [[ -d "$BUILD_CACHE_DIR/out" ]]; then
        cp -r "$BUILD_CACHE_DIR/out" . 2>/dev/null || true
        echo -e "${GREEN}🚀 Build restored from cache${NC}"
        return 0
    else
        return 1
    fi
}

# Check if test cache is valid
is_test_cache_valid() {
    local test_type="${1:-forge}"
    local current_source_hash=$(calculate_source_hash)
    local current_test_hash=$(calculate_test_hash)
    local current_config_hash=$(calculate_config_hash)

    local cache_file="$TEST_CACHE_DIR/${test_type}_results"
    local hash_file="$TEST_CACHE_DIR/${test_type}_hash"

    if [[ -f "$hash_file" ]] && [[ -f "$cache_file" ]]; then
        local cached_combined=$(cat "$hash_file")
        local current_combined="${current_source_hash}:${current_test_hash}:${current_config_hash}"
        [[ "$current_combined" == "$cached_combined" ]]
    else
        false
    fi
}

# Update test cache
update_test_cache() {
    local test_type="${1:-forge}"
    local test_result="${2:-0}"
    local test_output="${3:-}"

    local current_source_hash=$(calculate_source_hash)
    local current_test_hash=$(calculate_test_hash)
    local current_config_hash=$(calculate_config_hash)
    local current_combined="${current_source_hash}:${current_test_hash}:${current_config_hash}"

    echo "$current_combined" > "$TEST_CACHE_DIR/${test_type}_hash"
    echo "$test_result" > "$TEST_CACHE_DIR/${test_type}_results"
    echo "$(date -Iseconds)" > "$TEST_CACHE_DIR/${test_type}_timestamp"

    if [[ -n "$test_output" ]]; then
        echo "$test_output" > "$TEST_CACHE_DIR/${test_type}_output"
    fi

    echo -e "${GREEN}📊 Test cache updated for $test_type${NC}"
}

# Get cached test results
get_cached_test_results() {
    local test_type="${1:-forge}"
    local cache_file="$TEST_CACHE_DIR/${test_type}_results"
    local output_file="$TEST_CACHE_DIR/${test_type}_output"
    local timestamp_file="$TEST_CACHE_DIR/${test_type}_timestamp"

    if [[ -f "$cache_file" ]]; then
        local result=$(cat "$cache_file")
        local timestamp=$(cat "$timestamp_file" 2>/dev/null || echo "unknown")

        echo -e "${YELLOW}⚡ Using cached results for $test_type (from $timestamp)${NC}"

        if [[ -f "$output_file" ]]; then
            cat "$output_file"
        fi

        return "$result"
    else
        return 1
    fi
}

# Manage Echidna corpus cache
manage_echidna_cache() {
    local action="${1:-check}"
    local environment="${2:-local}"

    local corpus_dir="$ECHIDNA_CACHE_DIR/$environment"

    case "$action" in
        "init")
            mkdir -p "$corpus_dir"
            echo -e "${GREEN}📚 Echidna corpus cache initialized for $environment${NC}"
            ;;
        "path")
            echo "$corpus_dir"
            ;;
        "clean")
            rm -rf "$corpus_dir"
            mkdir -p "$corpus_dir"
            echo -e "${YELLOW}🧹 Echidna corpus cache cleaned for $environment${NC}"
            ;;
        "backup")
            local backup_dir="$ECHIDNA_CACHE_DIR/backup-$(date +%Y%m%d_%H%M%S)"
            cp -r "$corpus_dir" "$backup_dir" 2>/dev/null || true
            echo -e "${BLUE}💾 Echidna corpus backed up to $backup_dir${NC}"
            ;;
        *)
            if [[ -d "$corpus_dir" ]]; then
                return 0  # Cache exists
            else
                return 1  # Cache doesn't exist
            fi
            ;;
    esac
}

# Manage Scribble cache
manage_scribble_cache() {
    local action="${1:-check}"

    case "$action" in
        "init")
            mkdir -p "$SCRIBBLE_CACHE_DIR"
            echo -e "${GREEN}📋 Scribble cache initialized${NC}"
            ;;
        "clean")
            rm -rf "$SCRIBBLE_CACHE_DIR"/*
            echo -e "${YELLOW}🧹 Scribble cache cleaned${NC}"
            ;;
        "path")
            echo "$SCRIBBLE_CACHE_DIR"
            ;;
        *)
            [[ -d "$SCRIBBLE_CACHE_DIR" ]]
            ;;
    esac
}

# Clean all caches
clean_cache() {
    local cache_type="${1:-all}"

    case "$cache_type" in
        "build")
            rm -rf "$BUILD_CACHE_DIR"/*
            echo -e "${YELLOW}🧹 Build cache cleaned${NC}"
            ;;
        "test")
            rm -rf "$TEST_CACHE_DIR"/*
            echo -e "${YELLOW}🧹 Test cache cleaned${NC}"
            ;;
        "echidna")
            rm -rf "$ECHIDNA_CACHE_DIR"/*
            echo -e "${YELLOW}🧹 Echidna cache cleaned${NC}"
            ;;
        "scribble")
            manage_scribble_cache clean
            ;;
        "all")
            rm -rf "$CACHE_DIR"/*
            init_cache
            echo -e "${YELLOW}🧹 All caches cleaned${NC}"
            ;;
        *)
            echo -e "${RED}❌ Unknown cache type: $cache_type${NC}"
            echo "Available types: build, test, echidna, scribble, all"
            return 1
            ;;
    esac
}

# Show cache status
show_cache_status() {
    echo -e "${BLUE}📊 Cache Status Report${NC}"
    echo "====================="

    # Cache directories
    echo "Cache directories:"
    echo "  Base: $CACHE_DIR"
    echo "  Build: $BUILD_CACHE_DIR (exists: $(test -d "$BUILD_CACHE_DIR" && echo "✅" || echo "❌"))"
    echo "  Test: $TEST_CACHE_DIR (exists: $(test -d "$TEST_CACHE_DIR" && echo "✅" || echo "❌"))"
    echo "  Echidna: $ECHIDNA_CACHE_DIR (exists: $(test -d "$ECHIDNA_CACHE_DIR" && echo "✅" || echo "❌"))"
    echo "  Scribble: $SCRIBBLE_CACHE_DIR (exists: $(test -d "$SCRIBBLE_CACHE_DIR" && echo "✅" || echo "❌"))"
    echo ""

    # Build cache status
    echo "Build cache:"
    if is_build_cache_valid; then
        echo "  Status: ✅ Valid"
        local last_build=$(cat "$BUILD_CACHE_DIR/last_build" 2>/dev/null || echo "unknown")
        echo "  Last build: $last_build"
    else
        echo "  Status: ❌ Invalid or missing"
    fi
    echo ""

    # Test cache status
    echo "Test cache:"
    local test_types=("forge" "fuzz" "echidna" "scribble")
    for test_type in "${test_types[@]}"; do
        if is_test_cache_valid "$test_type"; then
            echo "  $test_type: ✅ Valid"
            local timestamp=$(cat "$TEST_CACHE_DIR/${test_type}_timestamp" 2>/dev/null || echo "unknown")
            echo "    Last run: $timestamp"
        else
            echo "  $test_type: ❌ Invalid or missing"
        fi
    done
    echo ""

    # Cache sizes
    echo "Cache sizes:"
    if command -v du >/dev/null 2>&1; then
        echo "  Total: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")"
        echo "  Build: $(du -sh "$BUILD_CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")"
        echo "  Test: $(du -sh "$TEST_CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")"
        echo "  Echidna: $(du -sh "$ECHIDNA_CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")"
        echo "  Scribble: $(du -sh "$SCRIBBLE_CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")"
    fi
}

# Main help function
show_help() {
    echo "Test Cache Manager - Intelligent caching for test optimization"
    echo ""
    echo "Usage:"
    echo "  $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  init                    - Initialize cache system"
    echo "  status                  - Show cache status"
    echo "  clean [type]           - Clean cache (types: build, test, echidna, scribble, all)"
    echo "  build-check            - Check if build cache is valid"
    echo "  build-update           - Update build cache"
    echo "  build-restore          - Restore build from cache"
    echo "  test-check <type>      - Check if test cache is valid"
    echo "  test-update <type> <result> [output] - Update test cache"
    echo "  test-get <type>        - Get cached test results"
    echo "  echidna-corpus <action> [env] - Manage Echidna corpus cache"
    echo "  scribble <action>      - Manage Scribble cache"
    echo ""
    echo "Examples:"
    echo "  $0 init                           # Initialize cache system"
    echo "  $0 status                         # Show cache status"
    echo "  $0 clean build                    # Clean build cache"
    echo "  $0 build-check                    # Check build cache validity"
    echo "  $0 test-check forge               # Check forge test cache"
    echo "  $0 echidna-corpus init ci         # Initialize CI Echidna corpus"
}

# Main execution
main() {
    local command="${1:-help}"

    # Ensure cache directory exists
    [[ ! -d "$CACHE_DIR" ]] && init_cache

    case "$command" in
        "init")
            init_cache
            ;;
        "status")
            show_cache_status
            ;;
        "clean")
            clean_cache "${2:-all}"
            ;;
        "build-check")
            if is_build_cache_valid; then
                echo -e "${GREEN}✅ Build cache is valid${NC}"
                exit 0
            else
                echo -e "${YELLOW}❌ Build cache is invalid${NC}"
                exit 1
            fi
            ;;
        "build-update")
            update_build_cache
            ;;
        "build-restore")
            if restore_build_cache; then
                exit 0
            else
                echo -e "${YELLOW}❌ No build cache to restore${NC}"
                exit 1
            fi
            ;;
        "test-check")
            local test_type="${2:-forge}"
            if is_test_cache_valid "$test_type"; then
                echo -e "${GREEN}✅ Test cache for $test_type is valid${NC}"
                exit 0
            else
                echo -e "${YELLOW}❌ Test cache for $test_type is invalid${NC}"
                exit 1
            fi
            ;;
        "test-update")
            local test_type="${2:-forge}"
            local result="${3:-0}"
            local output="${4:-}"
            update_test_cache "$test_type" "$result" "$output"
            ;;
        "test-get")
            local test_type="${2:-forge}"
            get_cached_test_results "$test_type"
            ;;
        "echidna-corpus")
            local action="${2:-check}"
            local env="${3:-local}"
            manage_echidna_cache "$action" "$env"
            ;;
        "scribble")
            local action="${2:-check}"
            manage_scribble_cache "$action"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            echo -e "${RED}❌ Unknown command: $command${NC}"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
