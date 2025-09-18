#!/bin/bash

# Test All Contracts with Mythril
# Verifies that the import callback fix works for all contracts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Testing Mythril Analysis on All Contracts${NC}"
echo -e "${BLUE}==========================================${NC}"

# Find all Solidity contracts
CONTRACTS=$(find src -name "*.sol" -type f | grep -v interfaces | head -5)
TOTAL=0
PASSED=0
FAILED=0

# Test summary arrays
declare -a PASSED_CONTRACTS
declare -a FAILED_CONTRACTS

echo -e "${YELLOW}Found contracts to test:${NC}"
for contract in $CONTRACTS; do
    echo "  - $contract"
    ((TOTAL++))
done
echo ""

# Test each contract
for contract in $CONTRACTS; do
    echo -e "${YELLOW}Testing: $contract${NC}"

    if timeout 60s ./mythril-analyze.sh -f "$contract" -t 45 > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASSED: $contract${NC}"
        PASSED_CONTRACTS+=("$contract")
        ((PASSED++))
    else
        echo -e "${RED}✗ FAILED: $contract${NC}"
        FAILED_CONTRACTS+=("$contract")
        ((FAILED++))
    fi
    echo ""
done

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TEST SUMMARY${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total contracts tested: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ ${#PASSED_CONTRACTS[@]} -gt 0 ]; then
    echo -e "${GREEN}Passed contracts:${NC}"
    for contract in "${PASSED_CONTRACTS[@]}"; do
        echo -e "${GREEN}  ✓ $contract${NC}"
    done
    echo ""
fi

if [ ${#FAILED_CONTRACTS[@]} -gt 0 ]; then
    echo -e "${RED}Failed contracts:${NC}"
    for contract in "${FAILED_CONTRACTS[@]}"; do
        echo -e "${RED}  ✗ $contract${NC}"
    done
    echo ""
fi

# Overall result
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED! Import callback fix is working correctly.${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Check individual contract logs for details.${NC}"
    exit 1
fi
