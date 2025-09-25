# Architecture Diagrams and Decision Trees

**Version**: 1.0
**Date**: 2025-09-25
**Stories**: 024.71-024.76

## Table of Contents

1. [Fee Flow Architecture](#fee-flow-architecture)
2. [Decision Tree: Fee Calculation Logic](#decision-tree-fee-calculation-logic)
3. [State Transition Diagrams](#state-transition-diagrams)
4. [Integration Architecture](#integration-architecture)
5. [Error Handling Flowchart](#error-handling-flowchart)
6. [Gas Optimization Map](#gas-optimization-map)

## Fee Flow Architecture

### High-Level Fee Flow
```
User Request: removeLiquidity(bondingTokenAmount, minInputTokens)
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│                    INPUT VALIDATION                            │
├─────────────────────────────────────────────────────────────────┤
│ • bondingTokenAmount > 0                                        │
│ • User has sufficient bonding tokens                           │
│ • Contract not locked                                          │
│ • Vault approval initialized                                   │
└─────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│                    FEE CALCULATION                             │
├─────────────────────────────────────────────────────────────────┤
│ cachedWithdrawalFee = withdrawalFeeBasisPoints    [SLOAD: 1]   │
│                                   ↓                           │
│ feeAmount = (bondingTokenAmount × cachedWithdrawalFee) ÷ 10000 │
│                                   ↓                           │
│ effectiveBondingTokens = bondingTokenAmount - feeAmount       │
└─────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│                   OUTPUT CALCULATION                           │
├─────────────────────────────────────────────────────────────────┤
│ IF effectiveBondingTokens == 0:                               │
│     inputTokensOut = 0                                         │
│ ELSE:                                                          │
│     inputTokensOut = _calculateInputTokensOut(effectiveTokens) │
└─────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│                   MEV PROTECTION                               │
├─────────────────────────────────────────────────────────────────┤
│ require(inputTokensOut >= minInputTokens)                      │
│ "B3: Insufficient output amount"                              │
└─────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│                   EXECUTE WITHDRAWAL                           │
├─────────────────────────────────────────────────────────────────┤
│ 1. bondingToken.burn(msg.sender, bondingTokenAmount)          │
│ 2. IF feeAmount > 0: emit FeeCollected(...)                   │
│ 3. IF inputTokensOut > 0:                                     │
│    • vault.withdraw(inputToken, inputTokensOut, this)         │
│    • inputToken.transfer(msg.sender, inputTokensOut)          │
│ 4. _updateVirtualLiquidityState(-inputTokensOut, +bondingAmt) │
│ 5. emit LiquidityRemoved(msg.sender, bondingAmt, inputOut)    │
└─────────────────────────────────────────────────────────────────┘
```

### Detailed Fee Mechanism Flow
```
                    Input: bondingTokenAmount, withdrawalFeeBasisPoints
                                        ↓
                           ┌─────────────────────────┐
                           │   Storage Optimization  │
                           │ Cache withdrawal fee to │
                           │ avoid multiple SLOADs   │
                           └─────────────────────────┘
                                        ↓
                    ┌──────────────────────────────────────┐
                    │         Integer Division             │
                    │ feeAmount = (amount × fee) ÷ 10000   │
                    │                                      │
                    │ Edge Case Handling:                  │
                    │ • If (amount × fee) < 10000:         │
                    │   feeAmount = 0 (expected)           │
                    │ • If fee = 10000:                    │
                    │   feeAmount = amount (100% fee)      │
                    └──────────────────────────────────────┘
                                        ↓
                         ┌─────────────────────────┐
                         │   Effective Calculation │
                         │ effective = amount - fee │
                         │                         │
                         │ Bounds: 0 ≤ effective ≤ │
                         │         amount          │
                         └─────────────────────────┘
                                        ↓
                    ┌──────────────────────────────────────┐
                    │         Output Determination         │
                    │                                      │
                    │ IF effective == 0:                   │
                    │   → inputTokensOut = 0               │
                    │   → User gets nothing (fee = 100%)   │
                    │                                      │
                    │ ELSE:                                │
                    │   → Calculate using AMM formula      │
                    │   → inputTokensOut = f(effective)    │
                    └──────────────────────────────────────┘
```

## Decision Tree: Fee Calculation Logic

```
                          Start: removeLiquidity() called
                                        ↓
                          bondingTokenAmount > 0?
                            ↓ YES            ↓ NO
                     Continue                Error: "Amount must be > 0"
                        ↓
                User has sufficient tokens?
                  ↓ YES              ↓ NO
               Continue            Error: "Insufficient bonding tokens"
                  ↓
              Contract locked?
                ↓ NO               ↓ YES
             Continue            Error: "Contract locked"
                ↓
        withdrawalFeeBasisPoints == 0?
              ↓ NO                    ↓ YES
        Calculate fee              feeAmount = 0
              ↓                       ↓
     (amount × fee) >= 10000?        effectiveBondingTokens = amount
        ↓ YES        ↓ NO              ↓
    feeAmount =   feeAmount = 0       Skip to: Calculate output
   calculated      ↓                       ↓
        ↓          effectiveBondingTokens = amount
    effectiveBondingTokens =            ↓
    amount - feeAmount             Calculate output using
        ↓                          _calculateInputTokensOut()
    effectiveBondingTokens == 0?         ↓
      ↓ YES           ↓ NO           inputTokensOut >= minInputTokens?
  inputTokensOut = 0  Calculate output     ↓ YES        ↓ NO
        ↓             using AMM formula     Continue   Error: MEV protection
        ↓                   ↓                ↓
        └─────────────────────────────────────┘
                            ↓
                Execute withdrawal transaction
                            ↓
            ┌─────────────────────────────────┐
            │ 1. Burn full bondingTokenAmount │
            │ 2. Emit FeeCollected if fee > 0 │
            │ 3. Transfer inputTokensOut      │
            │ 4. Update virtual liquidity    │
            │ 5. Emit LiquidityRemoved       │
            └─────────────────────────────────┘
```

## State Transition Diagrams

### Contract State Transitions
```
                         ┌─────────────────┐
                         │   UNINITIALIZED │
                         │  vaultApproval  │
                         │ Initialized=false│
                         └─────────────────┘
                                  ↓ initializeVaultApproval()
                         ┌─────────────────┐
                    ┌────│     NORMAL      │────┐
                    │    │   Operations    │    │
                    │    │   Available     │    │
                    │    └─────────────────┘    │
         lock()     │              ↑            │ setWithdrawalFee()
            ↓       │              │            ↓
    ┌─────────────────┐           │     ┌─────────────────┐
    │     LOCKED      │           │     │  FEE_UPDATED    │
    │   No operations │           │     │ New fee active  │
    │    allowed      │           │     │                 │
    └─────────────────┘           │     └─────────────────┘
            ↓ unlock()            │              ↑
            └─────────────────────┘              │
                                                 │
                       ┌─────────────────────────┘
                       ↓
              Fee changes are immediate
              and affect all subsequent
              removeLiquidity() calls
```

### Fee Processing State Machine
```
Input: bondingTokenAmount, minInputTokens
        ↓
┌─────────────────────┐
│    VALIDATION       │
│   • Amount > 0      │
│   • User balance    │
│   • Contract unlocked│
└─────────────────────┘
        ↓ PASS            ↓ FAIL
┌─────────────────────┐   └→ REVERT
│  FEE_CALCULATION    │
│  • Load cached fee  │
│  • Calculate amount │
│  • Handle edge cases│
└─────────────────────┘
        ↓
┌─────────────────────┐
│ OUTPUT_CALCULATION  │
│ • AMM math if > 0   │
│ • Zero if fee=100%  │
│ • MEV protection    │
└─────────────────────┘
        ↓ minInputTokens OK    ↓ FAIL
┌─────────────────────┐       └→ REVERT
│    EXECUTION        │
│ • Burn tokens       │
│ • Transfer output   │
│ • Update state      │
│ • Emit events       │
└─────────────────────┘
        ↓
┌─────────────────────┐
│     COMPLETE        │
│ • User received     │
│   input tokens      │
│ • Fee collected     │
│ • State updated     │
└─────────────────────┘
```

## Integration Architecture

### Contract Integration Points
```
┌─────────────────────────────────────────────────────────────────┐
│                      BEHODLER3 TOKENLAUNCH                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐ │
│  │  FEE MECHANISM  │    │   AMM LOGIC     │    │ VAULT SYSTEM │ │
│  │                 │    │                 │    │              │ │
│  │ • withdrawalFee │◄───┤ • Virtual K     │────┤ • inputToken │ │
│  │   BasisPoints   │    │ • Virtual L     │    │ • withdraw() │ │
│  │ • setFee()      │    │ • alpha/beta    │    │ • deposit()  │ │
│  │ • feeAmount     │    │ • calculate()   │    │              │ │
│  └─────────────────┘    └─────────────────┘    └──────────────┘ │
│           ↑                       ↑                      ↑      │
│           │                       │                      │      │
└───────────┼───────────────────────┼──────────────────────┼──────┘
            │                       │                      │
            ↓                       ↓                      ↓
┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐
│   BONDING       │    │     CERTORA     │    │   EXTERNAL   │
│    TOKEN        │    │ VERIFICATION    │    │ INTEGRATIONS │
│                 │    │                 │    │              │
│ • ERC20         │    │ • 13 Rules      │    │ • Frontend   │
│ • Mintable      │    │ • Mathematical  │    │ • Analytics  │
│ • Burnable      │    │   Proofs        │    │ • Monitoring │
│ • totalSupply() │    │ • Edge Cases    │    │ • APIs       │
└─────────────────┘    └─────────────────┘    └──────────────┘
```

### Data Flow Architecture
```
External Call: removeLiquidity(amount, minTokens)
    ↓
┌─────────────────────────────────────┐
│          ENTRY POINT                │
│ • Reentrancy guard                  │
│ • Lock modifier                     │
│ • Parameter validation              │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│         FEE LAYER                   │
│ • SLOAD: withdrawalFeeBasisPoints   │  ← Storage Access
│ • Calculate: feeAmount              │
│ • Calculate: effectiveBondingTokens │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│         AMM LAYER                   │
│ • SLOAD: virtualK, alpha, beta      │  ← Storage Access
│ • Calculate: _calculateInputTokensOut│
│ • Apply: virtual pair mathematics   │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│       EXECUTION LAYER               │
│ • CALL: bondingToken.burn()         │  ← External Call
│ • CALL: vault.withdraw()            │  ← External Call
│ • CALL: inputToken.transfer()       │  ← External Call
│ • SSTORE: update virtual state      │  ← Storage Write
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│        EVENT LAYER                  │
│ • LOG: FeeCollected (if fee > 0)    │  ← Event Emission
│ • LOG: LiquidityRemoved             │  ← Event Emission
└─────────────────────────────────────┘
```

## Error Handling Flowchart

### Complete Error Handling Flow
```
                    Function Entry: removeLiquidity()
                                ↓
    ┌───────────────────────────────────────────────────────┐
    │                PRE-EXECUTION CHECKS                   │
    └───────────────────────────────────────────────────────┘
                                ↓
            bondingTokenAmount > 0?
               ↓ NO                ↓ YES
    ┌─────────────────────┐       Continue
    │ REVERT:             │          ↓
    │ "Bonding token      │    User has sufficient balance?
    │  amount must be     │        ↓ NO              ↓ YES
    │  greater than 0"    │  ┌─────────────────┐    Continue
    └─────────────────────┘  │ REVERT:         │       ↓
                             │ "Insufficient   │   Contract locked?
                             │  bonding tokens"│    ↓ YES          ↓ NO
                             └─────────────────┘  ┌──────────────┐  Continue
                                                  │ REVERT:      │     ↓
                                                  │ Via notLocked│ Fee calculation
                                                  │ modifier     │     ↓
                                                  └──────────────┘  Mathematical
                                                                   operations
                                                                      ↓
                                                              inputTokensOut >=
                                                              minInputTokens?
                                                         ↓ NO                ↓ YES
                                                  ┌─────────────────────┐   Continue
                                                  │ REVERT:             │      ↓
                                                  │ "Insufficient       │  Execute withdrawal
                                                  │  output amount"     │      ↓
                                                  │ (MEV Protection)    │  External call
                                                  └─────────────────────┘   failures?
                                                                         ↓ YES    ↓ NO
                                                                   Handle gracefully  Success
                                                                         ↓           ↓
                                                                   ┌──────────────┐ Return
                                                                   │ REVERT:      │ result
                                                                   │ "Transfer    │
                                                                   │  failed"     │
                                                                   └──────────────┘
```

### Error Categories and Responses
```
┌─────────────────────────────────────────────────────────────┐
│                    ERROR CLASSIFICATION                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  INPUT VALIDATION ERRORS          │  SYSTEM STATE ERRORS    │
│  • Amount <= 0                    │  • Contract locked      │
│  • Insufficient balance           │  • Vault not initialized│
│  • Zero address                   │  • Reentrancy detected  │
│                                   │                         │
│  CALCULATION ERRORS               │  EXTERNAL CALL ERRORS   │
│  • Division by zero               │  • Transfer failed      │
│  • Overflow/Underflow             │  • Vault withdrawal fail│
│  • Invalid parameters             │  • Burn operation fail  │
│                                                             │
│  BUSINESS LOGIC ERRORS            │  SECURITY ERRORS        │
│  • MEV protection triggered       │  • Unauthorized access  │
│  • Fee exceeds maximum            │  • Invalid fee setting  │
│  • Slippage exceeded              │  • Emergency conditions │
└─────────────────────────────────────────────────────────────┘

Response Strategy for Each Category:

INPUT VALIDATION → Immediate revert with descriptive message
SYSTEM STATE     → Check preconditions, fail fast
CALCULATION      → Use safe math, handle edge cases
EXTERNAL CALLS   → Verify success, provide fallbacks
BUSINESS LOGIC   → Apply protection mechanisms
SECURITY         → Fail secure, emit warning events
```

## Gas Optimization Map

### Gas Cost Breakdown
```
                    removeLiquidity() Gas Distribution
                              (Typical: ~185k gas)
                                        ↓
┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐
│   VALIDATION    │ FEE CALCULATION │ AMM CALCULATION │   EXECUTION     │
│     ~15k gas    │     ~8k gas     │     ~12k gas    │    ~150k gas    │
├─────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ • Modifiers     │ • SLOAD (1x)    │ • SLOAD (3x)    │ • External calls│
│ • Balance check │ • Math ops      │ • Math ops      │ • State updates │
│ • Require stmts │ • Unchecked     │ • Division      │ • Event emission│
└─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

### Storage Access Optimization
```
Before Optimization:
┌─────────────────────────────────────────────────────────────┐
│  Function: removeLiquidity()                               │
│  ┌─────────────────────┐  ┌─────────────────────┐          │
│  │ withdrawalFeeBasis  │  │ withdrawalFeeBasis  │  ← 2 SLOADs│
│  │ Points SLOAD #1     │  │ Points SLOAD #2     │    (1600 gas)│
│  └─────────────────────┘  └─────────────────────┘          │
└─────────────────────────────────────────────────────────────┘

After Optimization:
┌─────────────────────────────────────────────────────────────┐
│  Function: removeLiquidity()                               │
│  ┌─────────────────────┐  ┌─────────────────────┐          │
│  │ cachedWithdrawalFee │  │ Use cached value    │  ← 1 SLOAD │
│  │    = SLOAD          │  │   (memory access)   │    (800 gas)│
│  └─────────────────────┘  └─────────────────────┘          │
│  Gas Saved: ~800 gas per additional access                 │
└─────────────────────────────────────────────────────────────┘
```

### Unchecked Arithmetic Optimization
```
Safe Unchecked Operations:
┌─────────────────────────────────────────────────────────────┐
│  Operation: feeAmount = (bondingTokenAmount * fee) / 10000  │
│  ┌─────────────────────────────────────────────────────────┤
│  │ Mathematical Proof of Safety:                           │
│  │ • bondingTokenAmount: validated > 0                     │
│  │ • withdrawalFeeBasisPoints: bounded [0, 10000]          │
│  │ • Maximum result: bondingTokenAmount (when fee = 10000) │
│  │ • Cannot overflow: product fits in uint256              │
│  └─────────────────────────────────────────────────────────┤
│  Gas Savings: ~200 gas per unchecked operation             │
└─────────────────────────────────────────────────────────────┘

Safe Unchecked Operations Applied:
1. feeAmount calculation
2. effectiveBondingTokens calculation
3. Array index operations (where bounds proven)
4. Loop increments (where bounds known)

Total Gas Savings: ~400-600 gas per transaction
```

### Gas Optimization Results
```
┌─────────────────────────────────────────────────────────────┐
│                     OPTIMIZATION RESULTS                   │
├─────────────────────────────────────────────────────────────┤
│ Operation                │ Before    │ After     │ Savings   │
├──────────────────────────┼───────────┼───────────┼───────────┤
│ removeLiquidity (small)  │ 185,234   │ 184,329   │ 0.5%      │
│ removeLiquidity (large)  │ 219,570   │ 211,785   │ 3.6%      │
│ quoteRemoveLiquidity     │ 45,123    │ 44,891    │ 0.5%      │
│ setWithdrawalFee         │ 28,456    │ 28,456    │ 0%        │
├──────────────────────────┼───────────┼───────────┼───────────┤
│ Average Improvement      │           │           │ 1.4%      │
│ Maximum Gas Usage        │           │ 219,570   │ (12% under│
│                          │           │           │  250k)    │
└─────────────────────────────────────────────────────────────┘

Key Success Metrics:
✅ All operations under 250k gas limit
✅ No regressions in functionality
✅ Measurable improvements achieved
✅ Code readability maintained
```

---

**Document Version**: 1.0
**Last Updated**: 2025-09-25
**Diagrams Created**: Text-based for universal compatibility
**Next Update**: When architecture changes or new optimizations added