#!/bin/bash
# Performance Benchmarking Script for Property-Based Testing
# Part of Story 024.53 - Performance Optimization

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/docs/reports"
CACHE_DIR="$SCRIPT_DIR/cache"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BENCHMARK_REPORT="$REPORTS_DIR/performance-benchmark-$TIMESTAMP.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create necessary directories
mkdir -p "$REPORTS_DIR" "$CACHE_DIR"

echo -e "${BLUE}🚀 Starting Performance Benchmark Suite${NC}"
echo "=============================================="

# Benchmark data structure
start_benchmark() {
    echo "{ \"benchmark_run\": { \"timestamp\": \"$(date -Iseconds)\", \"tests\": [" > "$BENCHMARK_REPORT"
}

end_benchmark() {
    # Remove trailing comma and close JSON
    sed -i '$ s/,$//' "$BENCHMARK_REPORT"
    echo "] } }" >> "$BENCHMARK_REPORT"
    echo -e "${GREEN}📊 Benchmark report saved to: $BENCHMARK_REPORT${NC}"
}

# Function to run and benchmark a specific test
benchmark_test() {
    local test_name="$1"
    local test_command="$2"
    local timeout_duration="${3:-60}"

    echo -e "${YELLOW}⏱️  Benchmarking: $test_name${NC}"

    local start_time=$(date +%s.%3N)
    local success=true
    local output_file=$(mktemp)

    # Run the test with timeout
    if timeout "$timeout_duration" bash -c "$test_command" > "$output_file" 2>&1; then
        local exit_code=0
    else
        local exit_code=$?
        success=false
    fi

    local end_time=$(date +%s.%3N)
    local duration=$(echo "$end_time - $start_time" | bc -l)

    # Extract relevant metrics from output
    local test_count=$(grep -o "tests.*passed\|test result:" "$output_file" | wc -l || echo "0")
    local error_count=$(grep -c "FAIL\|ERROR\|failed" "$output_file" || echo "0")

    # Memory usage (approximate)
    local memory_peak=$(ps -o pid,vsz,rss,comm -p $$ | tail -1 | awk '{print $2}' || echo "0")

    # Add to benchmark report
    cat >> "$BENCHMARK_REPORT" << EOF
    {
      "test_name": "$test_name",
      "duration_seconds": $duration,
      "success": $success,
      "exit_code": $exit_code,
      "test_count": $test_count,
      "error_count": $error_count,
      "memory_peak_kb": $memory_peak,
      "timeout_duration": $timeout_duration,
      "command": "$test_command"
    },
EOF

    if [ "$success" = true ]; then
        echo -e "${GREEN}✅ $test_name completed in ${duration}s${NC}"
    else
        echo -e "${RED}❌ $test_name failed/timeout after ${duration}s${NC}"
    fi

    rm -f "$output_file"
}

# Start benchmarking
start_benchmark

echo -e "${BLUE}📋 Running Core Build & Test Benchmarks${NC}"

# 1. Forge Build Benchmark
benchmark_test "forge_build" "forge build" 30

# 2. Basic Tests Benchmark
benchmark_test "forge_test_basic" "forge test --no-gas-report" 45

# 3. Gas Reporting Tests
benchmark_test "forge_test_gas" "forge test --gas-report" 60

echo -e "${BLUE}🔍 Running Property-Based Testing Benchmarks${NC}"

# 4. Quick Echidna Test
benchmark_test "echidna_quick" "export PATH='/home/justin/.local/bin:\$PATH'; echidna test/echidna/SimpleTest.sol --contract SimpleTest --test-limit 50 --seq-len 5" 30

# 5. Standard Echidna Test
benchmark_test "echidna_standard" "export PATH='/home/justin/.local/bin:\$PATH'; echidna test/echidna/SimpleTest.sol --contract SimpleTest --test-limit 100 --seq-len 10" 60

# 6. Extended Echidna Test
benchmark_test "echidna_extended" "export PATH='/home/justin/.local/bin:\$PATH'; echidna test/echidna/SimpleTest.sol --contract SimpleTest --test-limit 500 --seq-len 15" 120

echo -e "${BLUE}🎯 Running Fuzz Testing Benchmarks${NC}"

# 7. Quick Fuzz Test
benchmark_test "forge_fuzz_quick" "forge test --match-test 'fuzz' --fuzz-runs 100" 30

# 8. Standard Fuzz Test
benchmark_test "forge_fuzz_standard" "forge test --match-test 'fuzz' --fuzz-runs 1000" 60

# 9. Extended Fuzz Test
benchmark_test "forge_fuzz_extended" "forge test --match-test 'fuzz' --fuzz-runs 5000" 120

echo -e "${BLUE}📋 Running Scribble Benchmarks${NC}"

# 10. Scribble Check
benchmark_test "scribble_check" "npx scribble --check src/ScribbleValidationContract.sol" 20

# 11. Scribble Instrumentation
benchmark_test "scribble_instrument" "npx scribble --output-mode files src/ScribbleValidationContract.sol" 30

echo -e "${BLUE}🔒 Running Security Analysis Benchmarks${NC}"

# 12. Quick Slither Analysis
benchmark_test "slither_quick" "slither . --exclude-dependencies --disable-color --filter-paths 'test/,lib/'" 45

# 13. Solhint Analysis
benchmark_test "solhint_analysis" "npx solhint 'src/**/*.sol' 'test/**/*.sol'" 20

echo -e "${BLUE}🔗 Running Pre-commit Hook Benchmarks${NC}"

# 14. Pre-commit formatting
benchmark_test "precommit_format" "pre-commit run prettier --all-files" 30

# 15. Pre-commit quick tests
benchmark_test "precommit_quick_tests" "pre-commit run forge-test-quick --all-files" 15

# End benchmarking and generate summary
end_benchmark

echo -e "${BLUE}📊 Generating Performance Summary${NC}"

# Generate human-readable summary
SUMMARY_FILE="$REPORTS_DIR/performance-summary-$TIMESTAMP.md"

cat > "$SUMMARY_FILE" << 'EOF'
# Performance Benchmark Summary

## Overview
This report contains performance benchmarks for all testing components in the Behodler3 TokenLaunch property-based testing suite.

## Benchmark Categories

### Core Build & Test
- **forge_build**: Contract compilation time
- **forge_test_basic**: Basic test suite execution
- **forge_test_gas**: Gas reporting test execution

### Property-Based Testing
- **echidna_quick**: Fast property testing (50 tests, 5 seq)
- **echidna_standard**: Standard property testing (100 tests, 10 seq)
- **echidna_extended**: Extended property testing (500 tests, 15 seq)

### Fuzz Testing
- **forge_fuzz_quick**: Quick fuzz testing (100 runs)
- **forge_fuzz_standard**: Standard fuzz testing (1000 runs)
- **forge_fuzz_extended**: Extended fuzz testing (5000 runs)

### Static Analysis
- **scribble_check**: Scribble annotation validation
- **scribble_instrument**: Contract instrumentation
- **slither_quick**: Static analysis scan
- **solhint_analysis**: Solidity linting

### Pre-commit Integration
- **precommit_format**: Code formatting checks
- **precommit_quick_tests**: Fast pre-commit test suite

## Results
EOF

# Extract timing data and add to summary
echo "" >> "$SUMMARY_FILE"
echo "| Test Name | Duration (s) | Status | Test Count | Errors |" >> "$SUMMARY_FILE"
echo "|-----------|--------------|--------|------------|--------|" >> "$SUMMARY_FILE"

# Parse JSON and format table (requires jq, fallback if not available)
if command -v jq >/dev/null 2>&1; then
    jq -r '.benchmark_run.tests[] | "| \(.test_name) | \(.duration_seconds) | \(if .success then "✅" else "❌" end) | \(.test_count) | \(.error_count) |"' "$BENCHMARK_REPORT" >> "$SUMMARY_FILE"
else
    echo "| (jq not available - see JSON report for details) | - | - | - | - |" >> "$SUMMARY_FILE"
fi

echo "" >> "$SUMMARY_FILE"
echo "Generated on: $(date)" >> "$SUMMARY_FILE"
echo "Raw data: $(basename "$BENCHMARK_REPORT")" >> "$SUMMARY_FILE"

echo -e "${GREEN}📈 Performance summary saved to: $SUMMARY_FILE${NC}"

echo ""
echo -e "${GREEN}🎉 Performance Benchmark Complete!${NC}"
echo "=============================================="
echo "📊 JSON Report: $BENCHMARK_REPORT"
echo "📋 Summary Report: $SUMMARY_FILE"
echo ""
echo "💡 Use this data to:"
echo "   • Optimize slow-running tests"
echo "   • Configure appropriate timeouts"
echo "   • Set performance baselines"
echo "   • Compare performance across changes"
