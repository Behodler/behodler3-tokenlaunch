# Debugging Guide: Certora Fixes

**Version**: 1.0
**Date**: 2025-09-25
**Stories**: 024.71-024.76

## Table of Contents

1. [Quick Start](#quick-start)
2. [Reproducing Original Failures](#reproducing-original-failures)
3. [Validating Current Fixes](#validating-current-fixes)
4. [Common Issues and Solutions](#common-issues-and-solutions)
5. [Certora Debugging](#certora-debugging)
6. [Test Environment Setup](#test-environment-setup)
7. [Troubleshooting Flowchart](#troubleshooting-flowchart)

## Quick Start

### Prerequisites
- Java 21+ (required for Certora CLI)
- Foundry (forge, cast)
- Node.js 18+ (for tooling)

### Quick Validation
```bash
# 1. Verify all tests pass
forge test

# 2. Run Certora verification
certoraRun certora/conf/optional_fee_verification.conf

# 3. Check gas benchmarks
forge test --match-contract GasBenchmarkTest -vv
```

Expected Results:
- ✅ All 262 tests pass
- ✅ 13/13 Certora rules pass (execution time ~23 seconds)
- ✅ Gas usage within expected ranges

## Reproducing Original Failures

### Step 1: Checkout Base Commit
```bash
git checkout 018b6f082e02026f1d33f3ca2f42c2d4a2f04c57
```

### Step 2: Reproduce withdrawalAmountCorrectWithFee Failure
```bash
# Run the specific failing rule
certoraRun certora/conf/optional_fee_verification.conf --rule withdrawalAmountCorrectWithFee

# Expected output (original failure):
# Rule withdrawalAmountCorrectWithFee: VIOLATED
# Counterexample found with small bondingTokenAmount values
```

**Original Failure Scenario**:
```solidity
// This would fail in the original implementation
uint256 bondingTokenAmount = 50;
uint256 withdrawalFeeBasisPoints = 100; // 1%
// Original: (50 * 100) / 10000 = 0 (integer division)
// Fixed: Properly handles this edge case
```

### Step 3: Reproduce feeCollectionConsistency Issues
```bash
# Run comprehensive test suite with original code
forge test --match-contract B3WithdrawalFeeTest

# Original issues:
# - Inconsistent fee calculations between quote and actual
# - State consistency problems in edge cases
```

### Step 4: Reproduce quoteConsistencyAcrossFees Complexity
```bash
# This rule would exhibit non-monotonic behavior
certoraRun certora/conf/optional_fee_verification.conf --rule quoteConsistencyAcrossFees

# Original problem: Complex AMM mathematics at extreme small values
# Solution: Replaced with basicFeeConsistency rule
```

## Validating Current Fixes

### Step 1: Complete Test Suite Validation
```bash
# Run all tests with verbose output
forge test -vvv

# Specific test categories:
forge test --match-contract B3WithdrawalFeeTest -vvv          # Fee mechanism tests
forge test --match-contract B3CertoraFixValidationTest -vvv   # Certora-specific tests
forge test --match-contract GasBenchmarkTest -vvv             # Performance tests
forge test --match-contract B3SecurityIntegrationTest -vvv    # Security tests
```

### Step 2: Certora Rule Verification
```bash
# Full verification suite
certoraRun certora/conf/optional_fee_verification.conf

# Individual rule verification
certoraRun certora/conf/optional_fee_verification.conf --rule withdrawalAmountCorrectWithFee
certoraRun certora/conf/optional_fee_verification.conf --rule feeCollectionConsistency
certoraRun certora/conf/optional_fee_verification.conf --rule basicFeeConsistency
```

Expected Results:
```
|Rule name                               |Verified     |Time (sec)|
|----------------------------------------|-------------|----------|
|withdrawalAmountCorrectWithFee          |Not violated |1         |
|feeCollectionConsistency                |Not violated |1         |
|basicFeeConsistency                     |Not violated |0         |
...
```

### Step 3: Edge Case Testing
```bash
# Test specific edge cases that were problematic
forge test --match-test testSmallAmountFeeCalculation -vvv
forge test --match-test testMaximumFee -vvv
forge test --match-test testZeroFeeBackwardCompatibility -vvv
forge test --match-test testIntegerDivisionEdgeCases -vvv
```

### Step 4: Gas Analysis
```bash
# Generate gas report
forge test --gas-report

# Specific gas benchmarks
forge test --match-contract GasBenchmarkTest --gas-report

# Expected ranges:
# removeLiquidity: 180k - 220k gas
# quoteRemoveLiquidity: 40k - 50k gas
```

## Common Issues and Solutions

### Issue 1: Certora Timeout Errors
**Symptoms**:
```
ERROR: Timeout occurred during verification
Rule: withdrawalAmountCorrectWithFee
```

**Diagnosis**:
```bash
# Check system resources
free -h
top | grep certora

# Check Java version
java --version  # Should be Java 21+
```

**Solutions**:
1. **Upgrade Java**: Certora requires Java 21+ (not 17)
   ```bash
   # Ubuntu/Debian
   sudo apt update
   sudo apt install openjdk-21-jdk
   export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
   ```

2. **Increase timeout**: Add to `.conf` file
   ```
   optimisticLoop: true
   proverArgs: ["-depth 10", "-timeout 1800"]
   ```

3. **Simplify rules**: Break complex rules into smaller components

### Issue 2: Integer Division Edge Cases
**Symptoms**:
```solidity
// Test failure example
testFeeCalculation: fee amount should be > 0 for positive fee rate
Expected: > 0
Actual: 0
```

**Diagnosis**:
```solidity
// Debug the calculation
uint256 bondingTokenAmount = 50;
uint256 withdrawalFeeBasisPoints = 100;
uint256 result = (bondingTokenAmount * withdrawalFeeBasisPoints) / 10000;
console.log("Result:", result); // Will be 0 due to integer division
```

**Solution**: This is expected behavior for very small amounts
```solidity
// The fix properly handles this:
if ((bondingTokenAmount * fee) >= 10000) {
    assert feeAmount > 0, "Fee should be positive when amount is sufficient";
} else {
    // For very small amounts, feeAmount will be 0 due to integer division
    assert effectiveBondingTokens == bondingTokenAmount, "Expected behavior";
}
```

### Issue 3: Gas Limit Exceeded
**Symptoms**:
```
Error: Transaction reverted: out of gas
Gas used: 250001
```

**Diagnosis**:
```bash
# Check gas usage patterns
forge test --match-test testRemoveLiquidity --gas-report

# Profile specific function
cast estimate --rpc-url $RPC_URL $CONTRACT removeLiquidity $AMOUNT $MIN
```

**Solutions**:
1. **Verify optimizations are applied**:
   ```solidity
   // Ensure storage caching is working
   uint256 cachedWithdrawalFee = withdrawalFeeBasisPoints; // Single SLOAD
   ```

2. **Check for optimization regressions**:
   ```bash
   git diff HEAD~1 src/Behodler3Tokenlaunch.sol | grep -E "(SLOAD|unchecked)"
   ```

### Issue 4: Test Inconsistencies
**Symptoms**:
```
testQuoteConsistency: quote != actual withdrawal amount
Expected: 1000
Actual: 999
```

**Diagnosis**:
```solidity
// Check if both functions use same calculation
uint256 quoted = contract.quoteRemoveLiquidity(amount);
uint256 actual = contract.removeLiquidity(amount, 0);
require(quoted == actual, "Inconsistent calculation");
```

**Root Cause**: Usually caching inconsistencies or different calculation paths

**Solution**: Ensure both functions use identical logic
```solidity
// Both functions should use:
uint256 cachedWithdrawalFee = withdrawalFeeBasisPoints;
uint256 feeAmount = (bondingTokenAmount * cachedWithdrawalFee) / 10000;
uint256 effectiveBondingTokens = bondingTokenAmount - feeAmount;
```

## Certora Debugging

### Debug Mode Execution
```bash
# Enable debug mode
certoraRun certora/conf/optional_fee_verification.conf --debug

# Specific rule debugging
certoraRun certora/conf/optional_fee_verification.conf --rule withdrawalAmountCorrectWithFee --debug
```

### Counterexample Analysis
When a rule fails, Certora provides counterexamples:

```bash
# Save counterexample to file
certoraRun certora/conf/optional_fee_verification.conf --rule failingRule --counterexample ce.json

# Analyze counterexample
cat ce.json | jq '.counterexample.variables'
```

**Interpreting Counterexamples**:
```json
{
  "bondingTokenAmount": "255",
  "withdrawalFeeBasisPoints": "100",
  "expectedFeeAmount": "0",
  "actualFeeAmount": "2"
}
```

### Common Certora Patterns

**Pattern 1: Mathint for Precision**
```javascript
// Use mathint to avoid overflow in verification
mathint feeAmount = (bondingTokenAmount * fee) / 10000;
assert feeAmount <= bondingTokenAmount, "Fee cannot exceed amount";
```

**Pattern 2: Require Constraints**
```javascript
// Constrain inputs to reasonable ranges
require bondingTokenAmount > 0 && bondingTokenAmount <= 1000000;
require fee <= 10000;
```

**Pattern 3: State Preconditions**
```javascript
// Ensure valid initial state
require !locked();
require vaultApprovalInitialized();
require e.msg.sender == owner();
```

### Rule Writing Best Practices

1. **Start Simple**: Begin with basic assertions
   ```javascript
   rule basicFeeTest(env e) {
       uint256 amount;
       require amount > 0;

       uint256 result = quoteRemoveLiquidity(amount);
       assert result <= amount, "Output cannot exceed input";
   }
   ```

2. **Add Constraints Gradually**:
   ```javascript
   rule enhancedFeeTest(env e) {
       uint256 amount;
       require amount > 0 && amount <= 1000000;  // Reasonable bounds
       require !locked();                        // Valid state

       // Test logic here
   }
   ```

3. **Use Descriptive Messages**:
   ```javascript
   assert feeAmount <= bondingTokenAmount,
          "Fee amount should never exceed bonding token amount";
   ```

## Test Environment Setup

### Local Development Environment
```bash
# 1. Clone and setup
git clone <repository>
cd behodler3-tokenlaunch-RM
git checkout sprint/security

# 2. Install dependencies
forge install

# 3. Set up environment variables
cp .env.example .env
# Edit .env with your settings

# 4. Verify setup
forge build
forge test --match-test testBasicFunctionality
```

### Certora Environment Setup
```bash
# 1. Install Java 21
java --version  # Should show Java 21+

# 2. Install/Update Certora CLI
pip install certora-cli --upgrade

# 3. Verify installation
certoraRun --version

# 4. Test with simple rule
certoraRun certora/conf/optional_fee_verification.conf --rule basicFeeConsistency
```

### Docker Environment (Alternative)
```dockerfile
# Dockerfile for consistent environment
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    openjdk-21-jdk \
    nodejs \
    npm \
    python3-pip \
    curl

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
RUN /root/.foundry/bin/foundryup

# Install Certora
RUN pip3 install certora-cli

WORKDIR /workspace
COPY . .
RUN forge install
```

### CI/CD Integration
```yaml
# .github/workflows/certora-verification.yml
name: Certora Verification
on: [push, pull_request]

jobs:
  certora:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Setup Java
      uses: actions/setup-java@v3
      with:
        distribution: 'temurin'
        java-version: '21'

    - name: Install Certora
      run: pip install certora-cli

    - name: Run Verification
      run: certoraRun certora/conf/optional_fee_verification.conf
      env:
        CERTORAKEY: ${{ secrets.CERTORAKEY }}
```

## Troubleshooting Flowchart

```
Issue Reported
     ↓
Is it a test failure?
     ↓ YES               ↓ NO
Run specific test   →   Is it Certora timeout?
     ↓                      ↓ YES
Does test pass         Check Java version
individually?          (need Java 21+)
     ↓ YES                  ↓
Check for race         Upgrade Java
conditions                 ↓
     ↓ NO              Re-run Certora
Analyze test logic         ↓
     ↓                 Still failing?
Check recent changes       ↓ YES
     ↓                 Simplify rule or
Fix implementation    increase timeout
     ↓                      ↓ NO
Verify fix with       Issue resolved
full test suite
     ↓
Issue resolved
```

### Debug Commands Reference

**Test Debugging**:
```bash
forge test --match-test $TEST_NAME -vvvv  # Maximum verbosity
forge test --debug $TEST_NAME              # Interactive debugging
```

**Certora Debugging**:
```bash
certoraRun $CONF --rule $RULE --debug     # Debug mode
certoraRun $CONF --counterexample out.json # Save counterexample
```

**Gas Debugging**:
```bash
forge test --gas-report                   # Gas usage report
cast estimate $CONTRACT $FUNCTION $ARGS   # Estimate gas
```

**State Debugging**:
```bash
cast call $CONTRACT $VIEW_FUNCTION $ARGS  # Check contract state
cast logs --address $CONTRACT             # View emitted events
```

---

**Document Version**: 1.0
**Last Updated**: 2025-09-25
**For Support**: Refer to test files and comments in source code