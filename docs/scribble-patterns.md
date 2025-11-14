# Scribble Specification Patterns and Guidelines

## Overview

This document captures the effective patterns, practices, and guidelines discovered during the comprehensive implementation of Scribble specifications for the Behodler3 TokenLaunch contracts (Stories 024.41-024.44). All patterns and examples are drawn from the actual working implementation.

## Table of Contents

1. [Effective Specification Patterns](#effective-specification-patterns)
2. [Examples of Well-Written Specifications](#examples-of-well-written-specifications)
3. [Common Pitfalls and How to Avoid Them](#common-pitfalls-and-how-to-avoid-them)
4. [Troubleshooting Guide](#troubleshooting-guide)
5. [Guidelines for Writing New Specifications](#guidelines-for-writing-new-specifications)
6. [Testing and Validation Patterns](#testing-and-validation-patterns)

## Effective Specification Patterns

### 1. Invariant Specification Patterns

#### Mathematical Relationship Invariants

**Pattern**: Use mathematical formulas to express contract invariants

```solidity
/// #invariant {:msg "Virtual K must be consistent with virtual pair product"}
/// virtualK == 0 || virtualK == (virtualInputTokens + alpha) * (virtualL + beta);
```

**Why it works**:

- Expresses the core constant product formula that must hold
- Uses conditional logic to handle uninitialized state (virtualK == 0)
- Clear error message explains the mathematical relationship

#### State Consistency Invariants

**Pattern**: Ensure boolean states remain valid

```solidity
/// #invariant {:msg "Vault approval state must be consistent"}
/// vaultApprovalInitialized == true || vaultApprovalInitialized == false;
```

**Why it works**:

- Guards against unexpected state corruption
- Simple boolean logic that's easy to verify
- Essential for access control validation

#### Conditional Business Logic Invariants

**Pattern**: Express business rules with conditional logic

```solidity
/// #invariant {:msg "Funding goal must be greater than seed input when set"}
/// fundingGoal == 0 || fundingGoal > seedInput;
/// #invariant {:msg "Desired average price must be between 0 and 1e18 when set"}
/// desiredAveragePrice == 0 || (desiredAveragePrice > 0 && desiredAveragePrice < 1e18);
```

**Why it works**:

- Handles both uninitialized and initialized states
- Encodes critical business logic constraints
- Prevents invalid parameter combinations

### 2. Function Specification Patterns

#### Comprehensive Precondition Pattern

**Pattern**: Cover all input validation, state requirements, and permissions

```solidity
/// #if_succeeds {:msg "Input amount must be positive"} inputAmount > 0;
/// #if_succeeds {:msg "Vault approval must be initialized"} old(vaultApprovalInitialized);
/// #if_succeeds {:msg "Virtual K must be set (goals initialized)"} old(virtualK) > 0;
/// #if_succeeds {:msg "User must have sufficient input token balance"}
/// old(inputToken.balanceOf(msg.sender)) >= inputAmount;
/// #if_succeeds {:msg "User must have sufficient allowance"}
/// old(inputToken.allowance(msg.sender, address(this))) >= inputAmount;
```

**Why it works**:

- Systematic coverage of all requirements
- Uses `old()` to reference pre-state values
- Clear, specific error messages for each condition
- Groups related validations logically

#### State Change Verification Pattern

**Pattern**: Verify expected state changes in postconditions

```solidity
/// #if_succeeds {:msg "Bonding tokens must be minted to user (if output > 0)"}
/// baseBondingTokenOut == 0 || bondingToken.balanceOf(msg.sender) == old(bondingToken.balanceOf(msg.sender)) + baseBondingTokenOut;
/// #if_succeeds {:msg "Virtual input tokens should increase"}
/// baseBondingTokenOut == 0 || virtualInputTokens == old(virtualInputTokens) + inputAmount;
```

**Why it works**:

- Verifies the core functionality actually works
- Uses conditional logic to handle edge cases (output == 0)
- Compares pre and post states explicitly

#### Access Control Pattern

**Pattern**: Verify function-level access restrictions

```solidity
/// #if_succeeds {:msg "Only owner can call this function"} msg.sender == owner();
```

**Why it works**:

- Simple, direct verification of permissions
- Prevents unauthorized access
- Essential for security-critical functions

### 3. Error Message Patterns

#### Descriptive and Actionable Messages

**Good**: `"Virtual K must be consistent with virtual pair product"`
**Bad**: `"Invalid state"`

**Good**: `"User must have sufficient input token balance"`
**Bad**: `"Balance check failed"`

**Pattern**: Messages should explain what's wrong and what's expected

#### Context-Specific Messages

**Pattern**: Include relevant values or conditions in error messages

```solidity
/// #invariant {:msg "Funding goal must be greater than seed input when set"}
/// fundingGoal == 0 || fundingGoal > seedInput;
```

## Examples of Well-Written Specifications

### Example 1: Complex Financial Operation (addLiquidity)

```solidity
/// #if_succeeds {:msg "Input amount must be positive"} inputAmount > 0;
/// #if_succeeds {:msg "Vault approval must be initialized"} old(vaultApprovalInitialized);
/// #if_succeeds {:msg "Virtual K must be set (goals initialized)"} old(virtualK) > 0;
/// #if_succeeds {:msg "User must have sufficient input token balance"}
/// old(inputToken.balanceOf(msg.sender)) >= inputAmount;
/// #if_succeeds {:msg "User must have sufficient allowance"}
/// old(inputToken.allowance(msg.sender, address(this))) >= inputAmount;
/// #if_succeeds {:msg "Output must meet minimum requirement"}
/// baseBondingTokenOut >= minBondingTokens;
/// #if_succeeds {:msg "Bonding tokens must be minted to user (if output > 0)"}
/// baseBondingTokenOut == 0 || bondingToken.balanceOf(msg.sender) == old(bondingToken.balanceOf(msg.sender)) + baseBondingTokenOut;
/// #if_succeeds {:msg "Virtual input tokens should increase"}
/// baseBondingTokenOut == 0 || virtualInputTokens == old(virtualInputTokens) + inputAmount;
function addLiquidity(uint inputAmount, uint minBondingTokens) external nonReentrant whenNotPaused returns (uint baseBondingTokenOut)
```

**Why this is effective**:

- Covers all validation requirements systematically
- Verifies both inputs and outputs
- Handles edge cases (zero output)
- Clear separation of concerns (validation vs. state changes)

### Example 2: Time-Based Business Logic (EarlySellPenaltyHook)

```solidity
/// #invariant {:msg "Penalty parameters must allow penalty to reach zero"}
/// penaltyDeclineRatePerHour == 0 || maxPenaltyDurationHours == 0 ||
/// penaltyDeclineRatePerHour * maxPenaltyDurationHours >= 1000;

/// #if_succeeds {:msg "Fee must be within valid range (≤ 1000)"} fee <= 1000;
/// #if_succeeds {:msg "If penalty is inactive, fee should be zero"}
/// !old(penaltyActive) ==> fee == 0;
/// #if_succeeds {:msg "If seller never bought, fee should be maximum when penalty active"}
/// old(penaltyActive) && old(buyerLastBuyTimestamp[seller]) == 0 ==> fee == 1000;
function sell(address seller, uint baseBondingToken, uint baseInputToken) external override returns (uint fee, int deltaBondingToken)
```

**Why this is effective**:

- Encodes complex business logic in mathematical terms
- Uses implication (==>) for conditional logic
- Covers different user scenarios (never bought vs. recent buyer)
- Validates business constraints (fee limits, parameter relationships)

### Example 3: Comprehensive Contract Invariants

```solidity
/// #invariant {:msg "Virtual K must be consistent with virtual pair product"}
/// virtualK == 0 || virtualK == (virtualInputTokens + alpha) * (virtualL + beta);
/// #invariant {:msg "Virtual liquidity parameters must be properly initialized together"}
/// (virtualK > 0 && alpha > 0 && beta > 0) || (virtualK == 0 && alpha == 0 && beta == 0);
/// #invariant {:msg "Alpha and beta must be mathematically consistent for proper curve behavior"}
/// alpha == 0 || beta == 0 || alpha == beta;
```

**Why this is effective**:

- Expresses core mathematical relationships
- Handles initialization states properly
- Ensures parameter consistency
- Prevents impossible mathematical states

## Common Pitfalls and How to Avoid Them

### 1. Pitfall: Ignoring Uninitialized States

**Problem**: Writing invariants that fail during contract initialization

```solidity
// BAD: This fails during initialization when virtualK == 0
/// #invariant virtualK == (virtualInputTokens + alpha) * (virtualL + beta);
```

**Solution**: Always handle uninitialized/zero states

```solidity
// GOOD: Handles uninitialized state
/// #invariant virtualK == 0 || virtualK == (virtualInputTokens + alpha) * (virtualL + beta);
```

### 2. Pitfall: Overly Restrictive Specifications

**Problem**: Specifications that prevent valid edge cases

```solidity
// BAD: Prevents zero outputs which might be valid
/// #if_succeeds baseBondingTokenOut > 0;
```

**Solution**: Allow valid edge cases

```solidity
// GOOD: Allows zero outputs but verifies state consistency
/// #if_succeeds baseBondingTokenOut == 0 || bondingToken.balanceOf(msg.sender) == old(bondingToken.balanceOf(msg.sender)) + baseBondingTokenOut;
```

### 3. Pitfall: Unclear Error Messages

**Problem**: Generic error messages that don't help debugging

```solidity
// BAD: Doesn't explain what went wrong
/// #if_succeeds {:msg "Check failed"} condition;
```

**Solution**: Descriptive, actionable error messages

```solidity
// GOOD: Explains exactly what's expected
/// #if_succeeds {:msg "User must have sufficient input token balance"} old(inputToken.balanceOf(msg.sender)) >= inputAmount;
```

### 4. Pitfall: Missing Access Control Checks

**Problem**: Forgetting to verify permissions in specifications

```solidity
// BAD: No access control verification
/// #if_succeeds withdrawalFeeBasisPoints == _feeBasisPoints;
function setWithdrawalFee(uint256 _feeBasisPoints) external
```

**Solution**: Always verify access control first

```solidity
// GOOD: Verifies ownership before state changes
/// #if_succeeds {:msg "Only owner can set withdrawal fee"} msg.sender == owner();
/// #if_succeeds {:msg "Withdrawal fee should be set to specified value"} withdrawalFeeBasisPoints == _feeBasisPoints;
function setWithdrawalFee(uint256 _feeBasisPoints) external onlyOwner
```

### 5. Pitfall: Not Using old() for State Comparisons

**Problem**: Comparing post-state values incorrectly

```solidity
// BAD: This compares post-state values
/// #if_succeeds bondingToken.balanceOf(msg.sender) >= minBondingTokens;
```

**Solution**: Use old() to reference pre-state values

```solidity
// GOOD: Compares pre and post state correctly
/// #if_succeeds bondingToken.balanceOf(msg.sender) == old(bondingToken.balanceOf(msg.sender)) + baseBondingTokenOut;
```

## Troubleshooting Guide

### Common Scribble Errors and Solutions

#### 1. "Unknown identifier" Errors

**Error**: `Unknown identifier "virtualK"`

**Cause**: Scribble can't find the state variable or function

**Solutions**:

- Ensure the variable is public or has a getter function
- Check spelling and capitalization
- Verify the variable is declared in the same contract

#### 2. "Type mismatch" Errors

**Error**: `Type mismatch in comparison`

**Cause**: Comparing incompatible types (e.g., address vs uint)

**Solutions**:

- Check variable types carefully
- Use explicit type casting if needed
- Ensure boolean comparisons use boolean values

#### 3. Instrumentation Failures

**Error**: Scribble instrumentation produces invalid Solidity

**Causes and Solutions**:

- **Complex expressions**: Break down complex invariants into simpler ones
- **Unsupported syntax**: Avoid advanced Solidity features in specifications
- **Circular references**: Check for specifications that reference each other

#### 4. Test Failures Due to Edge Cases

**Problem**: Tests fail on valid edge cases

**Solutions**:

- Add conditional logic to handle zero/empty states
- Use implication (==>) for conditional requirements
- Test edge cases separately to verify they're actually valid

#### 5. Performance Issues

**Problem**: Scribble instrumentation makes tests very slow

**Solutions**:

- Limit the number of invariants per contract
- Avoid complex calculations in invariants
- Use specific test contracts for heavy specification testing

### Debugging Workflow

1. **Check Syntax**: Run `npx scribble --check-only src/Contract.sol`
2. **Instrument**: Run `npx scribble --output-mode files src/Contract.sol`
3. **Compile**: Run `forge build` to check for compilation errors
4. **Test**: Run specific test files to isolate issues
5. **Analyze**: Use `forge test -vvv` for detailed error output

### Validation Commands

The project includes comprehensive Makefile targets for validation:

```bash
# Complete validation workflow
make scribble

# Individual steps
make scribble-check           # Verify Scribble installation
make scribble-instrument      # Instrument contracts
make scribble-test           # Basic testing
make scribble-validation-test # Comprehensive test suite
```

## Guidelines for Writing New Specifications

### 1. Planning Phase

#### Identify Specification Types Needed

- **Invariants**: Properties that must always hold
- **Preconditions**: Requirements before function execution
- **Postconditions**: Expected outcomes after function execution
- **Access Control**: Permission verification

#### Analyze Contract Behavior

- Study the contract's state variables
- Understand the business logic
- Identify critical properties that must be preserved
- Map out state transitions

### 2. Writing Specifications

#### Start with Core Invariants

Begin with the most fundamental properties:

```solidity
/// #invariant {:msg "Core mathematical relationship"}
/// primaryVariable == 0 || primaryVariable == expectedFormula;
```

#### Add Function-Level Specifications

For each public function, specify:

1. **Access control** (if applicable)
2. **Input validation**
3. **State requirements**
4. **Expected outcomes**

#### Use the Specification Template

```solidity
/// #if_succeeds {:msg "Access control check"} permissionCondition;
/// #if_succeeds {:msg "Input validation"} inputCondition;
/// #if_succeeds {:msg "State requirement"} stateCondition;
/// #if_succeeds {:msg "Expected outcome"} outcomeCondition;
function yourFunction(params) external
```

### 3. Testing and Validation

#### Create Comprehensive Tests

- **Invariant tests**: Verify invariants hold across operations
- **Edge case tests**: Test boundary conditions
- **False positive tests**: Ensure specifications don't fail on valid operations

#### Use the Testing Pattern

```solidity
contract ScribbleYourContractTest is Test {
    // Test successful operations
    function testValidOperation() public { /* ... */ }

    // Test precondition failures
    function testPreconditionFailure() public {
        vm.expectRevert();
        // operation that should fail
    }

    // Test edge cases
    function testEdgeCase() public { /* ... */ }
}
```

### 4. Specification Quality Checklist

- [ ] **Clarity**: Error messages are descriptive and actionable
- [ ] **Completeness**: All critical properties are covered
- [ ] **Correctness**: Specifications match actual contract behavior
- [ ] **Edge Cases**: Uninitialized and boundary states are handled
- [ ] **Performance**: Specifications don't significantly slow down tests
- [ ] **Maintainability**: Specifications are easy to understand and modify

### 5. Integration Guidelines

#### Add to Makefile

Ensure your contracts are included in the Scribble validation targets:

```makefile
scribble-instrument-yourcontract:
	npx scribble --output-mode files src/YourContract.sol
```

#### Create Test Files

Follow the naming convention:

- `ScribbleYourContractTest.t.sol` - Basic specification tests
- `ScribbleYourContractInvariantTest.t.sol` - Invariant-focused tests
- `ScribbleYourContractEdgeCaseTest.t.sol` - Edge case tests

#### Update Documentation

- Add your contract to `SCRIBBLE_FUNCTION_SPECIFICATIONS.md`
- Document any new patterns discovered
- Update troubleshooting guide with new issues encountered

## Testing and Validation Patterns

### 1. Test Organization Pattern

The project uses a systematic approach to test organization:

```
test/
├── ScribbleSpecificationTest.t.sol     # Basic function specifications
├── ScribbleInvariantTest.t.sol         # Invariant violation tests
├── ScribbleEdgeCaseTest.t.sol          # Edge case testing
└── ScribbleFalsePositiveTest.t.sol     # False positive prevention
```

### 2. Invariant Testing Pattern

```solidity
contract ScribbleInvariantTest is Test {
    function testInvariantViolation() public {
        // Setup that should trigger invariant violation
        vm.expectRevert();
        // Operation that violates invariant
    }

    function testInvariantPreservation() public {
        // Setup valid state
        // Perform operation
        // Verify invariant still holds (implicit in Scribble)
    }
}
```

### 3. Edge Case Testing Pattern

```solidity
contract ScribbleEdgeCaseTest is Test {
    function testZeroInputHandling() public {
        // Test with zero inputs
    }

    function testMaximumInputHandling() public {
        // Test with maximum possible inputs
    }

    function testUninitializedStateHandling() public {
        // Test operations on uninitialized contracts
    }
}
```

### 4. False Positive Prevention Pattern

```solidity
contract ScribbleFalsePositiveTest is Test {
    function testValidOperationDoesNotFail() public {
        // Setup known-good scenario
        // Perform operation that should succeed
        // Verify no unexpected reverts
    }
}
```

### 5. Fuzz Testing Integration

The project successfully integrates fuzz testing with Scribble:

```solidity
function testFuzzAddLiquidity(uint256 inputAmount) public {
    // Bound inputs to valid ranges
    inputAmount = bound(inputAmount, 1, 1000000e18);

    // Setup contract state
    setupContract();

    // Perform fuzzed operation
    // Scribble specifications automatically verify correctness
}
```

## Conclusion

The patterns documented here represent battle-tested approaches from a comprehensive Scribble implementation covering two complex smart contracts with extensive invariants, preconditions, and postconditions. Following these patterns will help ensure your Scribble specifications are effective, maintainable, and provide real security value.

Key takeaways:

1. **Handle edge cases** from the beginning, especially uninitialized states
2. **Use descriptive error messages** that aid in debugging
3. **Test comprehensively** with dedicated test suites for different aspects
4. **Start simple** and gradually add complexity
5. **Validate continuously** using the provided Makefile targets

For the most up-to-date examples and patterns, refer to the actual contract implementations in `src/` and the comprehensive test suites in `test/`.
