# Comprehensive Function Specifications Report

## Overview

This document outlines the comprehensive Scribble specifications implemented for all public functions in the Behodler3 TokenLaunch contracts. The specifications include preconditions, postconditions, input validation, and access control checks.

## Contracts Covered

### 1. Behodler3Tokenlaunch.sol

#### Contract-Level Invariants

- **Virtual K Consistency**: `virtualK == 0 || virtualK == (virtualInputTokens + alpha) * (virtualL + beta)`
- **Parameter Initialization**: Virtual liquidity parameters must be properly initialized together
- **Lock State Consistency**: Contract lock state must be boolean
- **Vault Approval Consistency**: Vault approval state must be boolean
- **Funding Goal Validation**: Funding goal must be greater than seed input when set
- **Price Range Validation**: Desired average price must be between 0 and 1e18 when set

#### Function Specifications

##### setGoals(uint \_fundingGoal, uint \_seedInput, uint \_desiredAveragePrice)

**Access Control**: Only owner can call this function
**Preconditions**:

- Funding goal must be greater than seed input
- Seed input must be positive
- Desired average price must be between 0 and 1e18

**Postconditions**:

- Funding goal should be set correctly
- Seed input should be set correctly
- Desired average price should be set correctly
- Alpha should be calculated correctly using the formula
- Beta should equal alpha
- Virtual K should be calculated correctly
- Virtual input tokens should be set to seed input
- Virtual L should be calculated correctly

##### addLiquidity(uint inputAmount, uint minBondingTokens)

**Access Control**: Function is public but has lock protection
**Preconditions**:

- Input amount must be positive
- Contract must not be locked
- Vault approval must be initialized
- Virtual K must be set (goals initialized)
- User must have sufficient input token balance
- User must have sufficient allowance

**Postconditions**:

- Output must meet minimum requirement
- Bonding tokens must be minted to user (if output > 0)
- Virtual input tokens should increase

##### removeLiquidity(uint bondingTokenAmount, uint minInputTokens)

**Access Control**: Function is public but has lock protection
**Preconditions**:

- Bonding token amount must be positive
- Contract must not be locked
- User must have sufficient bonding tokens

**Postconditions**:

- Output must meet minimum requirement
- User bonding token balance should decrease
- Virtual input tokens should decrease if output > 0
- Input tokens should be transferred to user if output > 0

##### lock()

**Access Control**: Only owner can lock the contract
**Postconditions**:

- Contract should be locked after function call

##### unlock()

**Access Control**: Only owner can unlock the contract
**Postconditions**:

- Contract should be unlocked after function call

##### setAutoLock(bool \_autoLock)

**Access Control**: Only owner can set auto-lock
**Postconditions**:

- Auto-lock should be set to specified value

##### setHook(IBondingCurveHook \_hook)

**Access Control**: Only owner can set hook
**Postconditions**:

- Hook should be set to specified address

##### initializeVaultApproval()

**Access Control**: Only owner can initialize vault approval
**Preconditions**:

- Vault approval was not already initialized

**Postconditions**:

- Vault approval should be initialized after call

##### disableToken()

**Access Control**: Only owner can disable token
**Preconditions**:

- Vault approval must be initialized before disabling

**Postconditions**:

- Vault approval should be disabled after call

### 2. EarlySellPenaltyHook.sol

#### Contract-Level Invariants

- **Penalty Rate Validation**: Penalty decline rate must be positive if set
- **Duration Validation**: Max penalty duration must be positive if set
- **Parameter Consistency**: Penalty parameters must allow penalty to reach zero
- **Active State Consistency**: Penalty active state must be boolean

#### Function Specifications

##### buy(address buyer, uint baseBondingToken, uint baseInputToken)

**Access Control**: Public function (called by tokenlaunch contract)
**Preconditions**:

- Buyer address must not be zero

**Postconditions**:

- Buy operations never apply fees (fee == 0)
- Buy operations never adjust bonding tokens (deltaBondingToken == 0)
- Buyer timestamp should be updated to current block

##### sell(address seller, uint baseBondingToken, uint baseInputToken)

**Access Control**: Public function (called by tokenlaunch contract)
**Preconditions**:

- Seller address must not be zero

**Postconditions**:

- Fee must be within valid range (≤ 1000)
- Sell operations never adjust bonding tokens (deltaBondingToken == 0)
- If penalty is inactive, fee should be zero
- If seller never bought, fee should be maximum when penalty active

##### setPenaltyParameters(uint \_declineRatePerHour, uint \_maxDurationHours)

**Access Control**: Only owner can set penalty parameters
**Preconditions**:

- Decline rate must be positive
- Max duration must be positive
- Parameters must allow penalty to reach zero

**Postconditions**:

- Decline rate should be set correctly
- Max duration should be set correctly

##### setPenaltyActive(bool \_active)

**Access Control**: Only owner can set penalty active status
**Postconditions**:

- Penalty active should be set to specified value

## Input Validation Specifications

### Type-Level Validation

All functions include appropriate type validation through Solidity's type system and explicit checks:

1. **Address Validation**: Non-zero address checks where applicable
2. **Amount Validation**: Positive amount requirements for financial operations
3. **Permission Validation**: Owner-only function access control
4. **State Validation**: Contract state consistency checks (locked/unlocked, initialized/uninitialized)

### Range Validation

- **Percentage Values**: Fee values must be ≤ 1000 (100%)
- **Price Values**: Must be between 0 and 1e18
- **Time Values**: Positive duration requirements
- **Balance Checks**: Sufficient balance and allowance validation

## Access Control Specifications

### Owner-Only Functions

The following functions include comprehensive access control specifications:

- `setGoals()` - Virtual liquidity configuration
- `lock()` / `unlock()` - Emergency controls
- `setAutoLock()` - Auto-lock configuration
- `setHook()` - Hook management
- `initializeVaultApproval()` - Vault setup
- `disableToken()` - Emergency token disable
- `setPenaltyParameters()` - Penalty configuration
- `setPenaltyActive()` - Penalty state control

### Public Functions with State Guards

- `addLiquidity()` - Protected by lock state and initialization checks
- `removeLiquidity()` - Protected by lock state
- `buy()` / `sell()` - Hook functions with input validation

## Testing and Verification

### Scribble Instrumentation

All specifications have been tested with Scribble instrumentation to ensure:

1. Syntactic correctness of all annotations
2. Proper precondition and postcondition validation
3. Invariant preservation across function calls
4. Access control enforcement

### Test Coverage

A comprehensive test suite (`ScribbleSpecificationTest.t.sol`) validates:

- Precondition failures are properly caught
- Postconditions are verified on successful operations
- Invariants are preserved across multiple operations
- Multi-user scenarios work correctly
- Access control restrictions are enforced

## Conclusion

The implementation provides comprehensive function specifications covering:
✅ **Preconditions**: All public functions have appropriate input validation
✅ **Postconditions**: All state-changing functions have outcome verification
✅ **Input Validation**: Type, range, and semantic validation for all parameters
✅ **Access Control**: Owner-only functions and state-based access restrictions
✅ **Invariants**: Contract-level properties that must always hold
✅ **Testing**: Verified with both Scribble instrumentation and Foundry tests

This specification framework provides a solid foundation for formal verification and security auditing of the Behodler3 TokenLaunch contracts.
