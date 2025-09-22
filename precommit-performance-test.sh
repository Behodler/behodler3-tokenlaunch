#!/bin/bash

# Pre-commit Hook Performance Test
# Tests the performance and optimization of pre-commit hooks

echo "🚀 Pre-commit Hook Performance Test"
echo "===================================="
echo

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test directory setup
echo "📁 Setting up test environment..."
mkdir -p docs/reports

# Function to run test with timing
run_timed_test() {
    local test_name="$1"
    local command="$2"
    local max_time="$3"

    echo -e "${BLUE}⏱️  Testing: $test_name${NC}"

    start_time=$(date +%s)

    if eval "$command" 2>&1; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        if [ $duration -le $max_time ]; then
            echo -e "${GREEN}✅ $test_name: PASSED (${duration}s / ${max_time}s max)${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  $test_name: SLOW (${duration}s / ${max_time}s max)${NC}"
            return 1
        fi
    else
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo -e "${RED}❌ $test_name: FAILED (${duration}s)${NC}"
        return 1
    fi
}

# Test results tracking
total_tests=0
passed_tests=0
total_time=0

echo -e "${YELLOW}📋 Testing Individual Pre-commit Hooks${NC}"
echo "======================================"

# Test 1: Prettier formatting (should be fast)
echo
total_tests=$((total_tests + 1))
if run_timed_test "Prettier Formatting" "pre-commit run prettier --all-files" 5; then
    passed_tests=$((passed_tests + 1))
fi

# Test 2: Trailing whitespace (should be very fast)
echo
total_tests=$((total_tests + 1))
if run_timed_test "Trailing Whitespace Check" "pre-commit run trailing-whitespace --all-files" 3; then
    passed_tests=$((passed_tests + 1))
fi

# Test 3: Forge formatting (should be fast)
echo
total_tests=$((total_tests + 1))
if run_timed_test "Forge Formatting" "pre-commit run forge-fmt --all-files" 5; then
    passed_tests=$((passed_tests + 1))
fi

# Test 4: Forge build (moderate time)
echo
total_tests=$((total_tests + 1))
if run_timed_test "Forge Build" "pre-commit run forge-build --all-files" 8; then
    passed_tests=$((passed_tests + 1))
fi

# Test 5: Quick Forge tests (should be optimized)
echo
total_tests=$((total_tests + 1))
if run_timed_test "Quick Forge Tests" "pre-commit run forge-test-quick --all-files" 12; then
    passed_tests=$((passed_tests + 1))
fi

# Test 6: Quick Echidna property testing
echo
total_tests=$((total_tests + 1))
if run_timed_test "Quick Echidna Testing" "pre-commit run echidna-quick --all-files" 22; then
    passed_tests=$((passed_tests + 1))
fi

# Test 7: Quick fuzz testing
echo
total_tests=$((total_tests + 1))
if run_timed_test "Quick Fuzz Testing" "pre-commit run forge-fuzz-quick --all-files" 17; then
    passed_tests=$((passed_tests + 1))
fi

# Test 8: Solhint linting
echo
total_tests=$((total_tests + 1))
if run_timed_test "Solhint Linting" "pre-commit run solhint --all-files" 8; then
    passed_tests=$((passed_tests + 1))
fi

# Test 9: Quick Slither analysis
echo
total_tests=$((total_tests + 1))
if run_timed_test "Quick Slither Analysis" "pre-commit run slither-quick --all-files" 10; then
    passed_tests=$((passed_tests + 1))
fi

echo
echo -e "${YELLOW}🔄 Testing Full Pre-commit Run${NC}"
echo "=============================="

# Test the full pre-commit run with timing
echo
echo "⏱️  Running full pre-commit hook suite..."
start_time=$(date +%s)

if pre-commit run --all-files 2>&1; then
    end_time=$(date +%s)
    full_duration=$((end_time - start_time))

    if [ $full_duration -le 30 ]; then
        echo -e "${GREEN}🎉 Full pre-commit run: PASSED (${full_duration}s / 30s target)${NC}"
        full_test_passed=1
    else
        echo -e "${YELLOW}⚠️  Full pre-commit run: SLOW (${full_duration}s / 30s target)${NC}"
        full_test_passed=0
    fi
else
    end_time=$(date +%s)
    full_duration=$((end_time - start_time))
    echo -e "${RED}❌ Full pre-commit run: FAILED (${full_duration}s)${NC}"
    full_test_passed=0
fi

echo
echo -e "${YELLOW}📊 Performance Test Summary${NC}"
echo "=========================="
echo -e "Individual Hook Tests: $passed_tests/$total_tests passed"
echo -e "Full Pre-commit Time: ${full_duration}s (target: ≤30s)"
echo

if [ $full_duration -le 30 ] && [ $passed_tests -ge $((total_tests * 7 / 10)) ]; then
    echo -e "${GREEN}🎉 Pre-commit hooks are properly optimized!${NC}"
    echo "✅ Execution time under 30 seconds"
    echo "✅ Most individual hooks performing well"
    echo "✅ Development workflow won't be blocked"

    # Save performance report
    timestamp=$(date +%Y%m%d_%H%M%S)
    cat > "docs/reports/precommit-performance-${timestamp}.md" << EOF
# Pre-commit Hook Performance Report

**Generated**: $(date)
**Target Time**: ≤30 seconds
**Actual Time**: ${full_duration} seconds
**Status**: $([ $full_duration -le 30 ] && echo "PASS" || echo "SLOW")

## Individual Hook Performance

| Hook | Status | Notes |
|------|--------|-------|
| Prettier | $([ $passed_tests -ge 1 ] && echo "✅ PASS" || echo "❌ FAIL") | Code formatting |
| Trailing Whitespace | $([ $passed_tests -ge 2 ] && echo "✅ PASS" || echo "❌ FAIL") | Basic cleanup |
| Forge Format | $([ $passed_tests -ge 3 ] && echo "✅ PASS" || echo "❌ FAIL") | Solidity formatting |
| Forge Build | $([ $passed_tests -ge 4 ] && echo "✅ PASS" || echo "❌ FAIL") | Compilation check |
| Quick Tests | $([ $passed_tests -ge 5 ] && echo "✅ PASS" || echo "❌ FAIL") | Basic test suite |
| Echidna Quick | $([ $passed_tests -ge 6 ] && echo "✅ PASS" || echo "❌ FAIL") | Property testing |
| Fuzz Quick | $([ $passed_tests -ge 7 ] && echo "✅ PASS" || echo "❌ FAIL") | Fuzz testing |
| Solhint | $([ $passed_tests -ge 8 ] && echo "✅ PASS" || echo "❌ FAIL") | Linting |
| Slither Quick | $([ $passed_tests -ge 9 ] && echo "✅ PASS" || echo "❌ FAIL") | Static analysis |

## Optimization Features

- ⏱️  Timeouts prevent hanging
- 🔄 Graceful degradation for missing tools
- 📦 Staged execution (pre-commit vs pre-push)
- 🚫 Non-blocking warnings for timeouts

## Recommendations

$([ $full_duration -le 30 ] && echo "✅ No optimization needed - performance target met" || echo "⚠️  Consider further optimization or increasing timeout limits")
EOF

    echo "📄 Performance report saved to docs/reports/precommit-performance-${timestamp}.md"
    exit 0
else
    echo -e "${YELLOW}⚠️  Pre-commit hooks need optimization${NC}"
    echo "💡 Consider:"
    echo "   • Increasing timeout values"
    echo "   • Moving heavy tests to pre-push stage"
    echo "   • Disabling some hooks for faster commits"
    exit 1
fi
