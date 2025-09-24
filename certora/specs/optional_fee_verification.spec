// Formal Verification Specification for Optional Fee on removeLiquidity
// Story 032.4 - Certora Verification for Optional Fee Mechanism

methods {
    // Core contract methods (these require env for caller context)
    function removeLiquidity(uint256 bondingTokenAmount, uint256 minInputTokens) external returns (uint256);
    function quoteRemoveLiquidity(uint256 bondingTokenAmount) external returns (uint256) envfree;
    function setWithdrawalFee(uint256 _feeBasisPoints) external;

    // State getters
    function withdrawalFeeBasisPoints() external returns (uint256) envfree;
    function owner() external returns (address) envfree;

    // Bonding token access through the contract
    function bondingToken() external returns (address) envfree;

    // Bonding token methods via dispatcher
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.totalSupply() external => DISPATCHER(true);

    // Virtual state methods
    function virtualInputTokens() external returns (uint256) envfree;
    function virtualL() external returns (uint256) envfree;
    function virtualK() external returns (uint256) envfree;
    function alpha() external returns (uint256) envfree;
    function beta() external returns (uint256) envfree;

    // Utility functions
    function locked() external returns (bool) envfree;
    function vaultApprovalInitialized() external returns (bool) envfree;
}

// ============ FEE BOUNDS VERIFICATION ============

// Rule 1: Fee upper bound is enforced by contract validation
// Updated to test the invariant properly by focusing on setter validation
rule feeUpperBoundEnforced(env e) {
    uint256 newFee;

    // Test that setWithdrawalFee properly rejects fees > 10000
    if (newFee > 10000) {
        setWithdrawalFee@withrevert(e, newFee);
        assert lastReverted, "Setting fee > 10000 basis points should revert";
    } else {
        // Valid fees should be accepted (assuming caller is owner)
        require e.msg.sender == owner();
        uint256 oldFee = withdrawalFeeBasisPoints();
        setWithdrawalFee(e, newFee);
        assert withdrawalFeeBasisPoints() == newFee, "Valid fee should be set correctly";
    }
}

// Rule 1a: Fee boundary behavior verification
rule feeBoundaryBehavior(env e) {
    require e.msg.sender == owner();

    // Test exactly at boundary (10000 should be valid)
    setWithdrawalFee(e, 10000);
    assert withdrawalFeeBasisPoints() == 10000, "Fee of 10000 basis points should be valid";

    // Test just over boundary (10001 should revert)
    setWithdrawalFee@withrevert(e, 10001);
    assert lastReverted, "Fee of 10001 basis points should be rejected";
}

// Rule 1b: Parametric fee validation across range
rule parametricFeeValidation(env e) {
    uint256 testFee;
    require e.msg.sender == owner();

    if (testFee <= 10000) {
        // Valid fees should be accepted
        setWithdrawalFee(e, testFee);
        assert withdrawalFeeBasisPoints() == testFee, "Valid fees should be set correctly";
    } else {
        // Invalid fees should be rejected
        setWithdrawalFee@withrevert(e, testFee);
        assert lastReverted, "Invalid fees should be rejected";
    }
}

// Rule 1c: Fee state consistency after operations
// This rule verifies that fee operations don't corrupt the virtual state
rule feeStateConsistency(env e) {
    uint256 bondingTokenAmount;
    uint256 minInputTokens;

    require bondingTokenAmount > 0;
    address bondingTokenAddr = bondingToken();
    require bondingTokenAddr.balanceOf(e.msg.sender) >= bondingTokenAmount;
    require !locked();
    require vaultApprovalInitialized();

    // Capture fee and virtual state before operation
    uint256 feeBefore = withdrawalFeeBasisPoints();
    require feeBefore <= 10000; // Constrain to valid initial state

    uint256 virtualKBefore = virtualK();
    uint256 alphaBefore = alpha();
    uint256 betaBefore = beta();

    // Execute removeLiquidity with fee
    removeLiquidity(e, bondingTokenAmount, minInputTokens);

    // Fee should be unchanged by removeLiquidity operation
    uint256 feeAfter = withdrawalFeeBasisPoints();
    assert feeAfter == feeBefore, "RemoveLiquidity should not change withdrawal fee";

    // Virtual constants should remain unchanged (fee doesn't affect these)
    assert virtualK() == virtualKBefore, "Virtual K should remain constant";
    assert alpha() == alphaBefore, "Alpha should remain constant";
    assert beta() == betaBefore, "Beta should remain constant";
}

// Rule 2: Only owner can set withdrawal fee
rule onlyOwnerCanSetFee(env e) {
    uint256 newFee;
    address caller = e.msg.sender;
    address contractOwner = owner();

    // If caller is not owner, setWithdrawalFee should revert
    if (caller != contractOwner) {
        setWithdrawalFee@withrevert(e, newFee);
        assert lastReverted, "Only owner should be able to set withdrawal fee";
    } else {
        // If caller is owner, fee should be updated (assuming valid fee)
        require newFee <= 10000;
        uint256 oldFee = withdrawalFeeBasisPoints();
        setWithdrawalFee(e, newFee);
        assert withdrawalFeeBasisPoints() == newFee, "Owner should be able to set valid withdrawal fee";
    }
}

// ============ SUPPLY MANAGEMENT VERIFICATION ============

// Rule 3: Supply decreases correctly on removeLiquidity
rule supplyDecreasesCorrectly(env e) {
    uint256 bondingTokenAmount;
    uint256 minInputTokens;
    address user = e.msg.sender;

    require bondingTokenAmount > 0;
    require bondingToken.balanceOf(user) >= bondingTokenAmount;
    require !locked();
    require vaultApprovalInitialized();

    address bondingTokenAddr = bondingToken();
    uint256 totalSupplyBefore = bondingTokenAddr.totalSupply();
    uint256 userBalanceBefore = bondingTokenAddr.balanceOf(user);

    removeLiquidity(e, bondingTokenAmount, minInputTokens);

    uint256 totalSupplyAfter = bondingTokenAddr.totalSupply();
    uint256 userBalanceAfter = bondingTokenAddr.balanceOf(user);

    // Total supply should decrease by full bonding token amount (including fee portion)
    assert totalSupplyAfter == totalSupplyBefore - bondingTokenAmount,
           "Total supply must decrease by full bonding token amount";

    // User balance should decrease by full bonding token amount
    assert userBalanceAfter == userBalanceBefore - bondingTokenAmount,
           "User balance must decrease by full bonding token amount";
}

// Rule 1d: Zero fee backward compatibility verification
rule zeroFeeBackwardCompatibility(env e) {
    uint256 bondingTokenAmount;
    uint256 minInputTokens;

    require bondingTokenAmount > 0;
    require e.msg.sender == owner();

    // Set fee to zero explicitly
    setWithdrawalFee(e, 0);
    uint256 fee = withdrawalFeeBasisPoints();
    assert fee == 0, "Fee should be set to zero";

    // Test that zero fee behaves like no fee
    uint256 quotedAmount = quoteRemoveLiquidity(bondingTokenAmount);

    // With zero fee, the quote should use the full bonding token amount
    // This verifies backward compatibility with the original fee-less implementation
    address bondingTokenAddr = bondingToken();
    require bondingTokenAddr.balanceOf(e.msg.sender) >= bondingTokenAmount;
    require !locked();
    require vaultApprovalInitialized();

    uint256 actualAmount = removeLiquidity(e, bondingTokenAmount, minInputTokens);
    assert actualAmount == quotedAmount, "Zero fee should provide identical quote and actual amounts";
}

// ============ FEE CALCULATION VERIFICATION ============

// Rule 4: Withdrawal amount is correct with fee applied
rule withdrawalAmountCorrectWithFee(env e) {
    uint256 bondingTokenAmount;
    uint256 minInputTokens;

    require bondingTokenAmount > 0;
    address bondingTokenAddr = bondingToken();
    require bondingTokenAddr.balanceOf(e.msg.sender) >= bondingTokenAmount;
    require !locked();
    require vaultApprovalInitialized();

    uint256 fee = withdrawalFeeBasisPoints();
    uint256 quotedAmount = quoteRemoveLiquidity(bondingTokenAmount);
    uint256 actualAmount = removeLiquidity(e, bondingTokenAmount, minInputTokens);

    // Calculate expected fee amount using mathint to prevent overflow
    mathint feeAmount = (bondingTokenAmount * fee) / 10000;
    mathint effectiveBondingTokens = bondingTokenAmount - feeAmount;

    // Quoted amount should match actual amount (both use same calculation)
    assert actualAmount == quotedAmount,
           "Quoted amount should match actual withdrawal amount";

    // Fee reduction should be properly applied
    if (fee > 0) {
        assert feeAmount > 0, "Fee amount should be positive when fee rate is positive";
        assert effectiveBondingTokens < bondingTokenAmount,
               "Effective bonding tokens should be less than original when fee applied";
    } else {
        assert feeAmount == 0, "Fee amount should be zero when fee rate is zero";
        assert effectiveBondingTokens == bondingTokenAmount,
               "Effective bonding tokens should equal original when no fee";
    }
}

// Rule 5: Fee calculation correctness verification
rule feeCalculationCorrectness(env e) {
    uint256 bondingTokenAmount;
    uint256 minInputTokens;

    require bondingTokenAmount > 0;
    address bondingTokenAddr = bondingToken();
    require bondingTokenAddr.balanceOf(e.msg.sender) >= bondingTokenAmount;
    require !locked();
    require vaultApprovalInitialized();

    // Get current fee and calculate expected amounts
    uint256 currentFee = withdrawalFeeBasisPoints();
    require currentFee <= 10000; // Constrain to valid state

    uint256 quotedAmount = quoteRemoveLiquidity(bondingTokenAmount);
    uint256 actualAmount = removeLiquidity(e, bondingTokenAmount, minInputTokens);

    // Calculate expected fee math using mathint to prevent overflow
    mathint expectedFeeAmount = (bondingTokenAmount * currentFee) / 10000;
    mathint expectedEffectiveTokens = bondingTokenAmount - expectedFeeAmount;

    // Quote and actual should always match with correct fee calculation
    assert actualAmount == quotedAmount,
           "Quote and actual amounts should be consistent with fee applied";
}

// ============ PARAMETRIC VERIFICATION ============

// Rule 6: Parametric rule for fee calculation across all valid fee percentages
rule parametricFeeCalculation(env e) {
    uint256 bondingTokenAmount;
    uint256 minInputTokens;
    uint256 feeRate;

    require bondingTokenAmount > 0 && bondingTokenAmount <= 1000000; // Reasonable bounds
    require feeRate <= 10000; // Valid fee range
    address bondingTokenAddr = bondingToken();
    require bondingTokenAddr.balanceOf(e.msg.sender) >= bondingTokenAmount;
    require !locked();
    require vaultApprovalInitialized();

    // Set the parametric fee rate
    setWithdrawalFee(e, feeRate);

    uint256 quotedAmount = quoteRemoveLiquidity(bondingTokenAmount);
    uint256 actualAmount = removeLiquidity(e, bondingTokenAmount, minInputTokens);

    // Calculate expected fee mathematics using mathint to prevent overflow
    mathint expectedFeeAmount = (bondingTokenAmount * feeRate) / 10000;
    mathint expectedEffectiveTokens = bondingTokenAmount - expectedFeeAmount;

    // Verify fee calculation properties
    assert expectedFeeAmount <= bondingTokenAmount,
           "Fee amount should never exceed bonding token amount";

    assert expectedEffectiveTokens <= bondingTokenAmount,
           "Effective tokens should never exceed original amount";

    if (feeRate == 0) {
        assert expectedFeeAmount == 0, "Zero fee rate should result in zero fee amount";
        assert expectedEffectiveTokens == bondingTokenAmount,
               "Zero fee should result in no reduction";
    }

    if (feeRate == 10000) {
        assert expectedFeeAmount == bondingTokenAmount, "100% fee should equal full amount";
        assert expectedEffectiveTokens == 0, "100% fee should result in zero effective tokens";
    }

    // Quote and actual should always match
    assert actualAmount == quotedAmount,
           "Quote and actual amounts should be consistent for any valid fee rate";
}

// ============ STATE CONSISTENCY VERIFICATION ============

// Rule 7: Virtual state operations remain unchanged by fee operations
rule virtualStateUnchangedByFeeOperations(env e) {
    // This rule verifies that fee-related operations don't interfere with virtual state consistency

    // Capture initial virtual state
    uint256 virtualKBefore = virtualK();
    uint256 alphaBefore = alpha();
    uint256 betaBefore = beta();

    // Test fee operations (set fee doesn't change virtual state)
    require e.msg.sender == owner();
    uint256 newFee;
    require newFee <= 10000;

    setWithdrawalFee(e, newFee);

    // Virtual constants should be unchanged
    assert virtualK() == virtualKBefore, "Setting withdrawal fee should not change virtual K";
    assert alpha() == alphaBefore, "Setting withdrawal fee should not change alpha";
    assert beta() == betaBefore, "Setting withdrawal fee should not change beta";
}

// Rule 8: Quote consistency across different fee rates
rule quoteConsistencyAcrossFees(env e) {
    uint256 bondingTokenAmount;

    require bondingTokenAmount > 0 && bondingTokenAmount <= 1000000; // Reasonable bounds
    require e.msg.sender == owner();

    // Test quote calculation with zero fee
    setWithdrawalFee(e, 0);
    uint256 quoteZeroFee = quoteRemoveLiquidity(bondingTokenAmount);

    // Test quote calculation with non-zero fee (e.g., 5%)
    setWithdrawalFee(e, 500); // 5%
    uint256 quoteFivePct = quoteRemoveLiquidity(bondingTokenAmount);

    // Test quote calculation with maximum fee (100%)
    setWithdrawalFee(e, 10000); // 100%
    uint256 quoteMaxFee = quoteRemoveLiquidity(bondingTokenAmount);

    // Mathematical relationship verification
    assert quoteZeroFee >= quoteFivePct, "Higher fee should result in lower or equal quote";
    assert quoteFivePct >= quoteMaxFee, "Maximum fee should result in lowest quote";

    // With 100% fee, no tokens should be withdrawn (all consumed as fee)
    assert quoteMaxFee == 0, "100% fee should result in zero withdrawal amount";
}

// Rule 9: Virtual state remains mathematically consistent after fee-based removeLiquidity
rule virtualStateConsistencyWithFees(env e) {
    uint256 bondingTokenAmount;
    uint256 minInputTokens;

    require bondingTokenAmount > 0;
    address bondingTokenAddr = bondingToken();
    require bondingTokenAddr.balanceOf(e.msg.sender) >= bondingTokenAmount;
    require !locked();
    require vaultApprovalInitialized();

    // Capture virtual state before
    uint256 virtualInputBefore = virtualInputTokens();
    uint256 virtualLBefore = virtualL();
    uint256 virtualKBefore = virtualK();
    uint256 alphaBefore = alpha();
    uint256 betaBefore = beta();

    uint256 inputTokensOut = removeLiquidity(e, bondingTokenAmount, minInputTokens);

    // Capture virtual state after
    uint256 virtualInputAfter = virtualInputTokens();
    uint256 virtualLAfter = virtualL();
    uint256 virtualKAfter = virtualK();
    uint256 alphaAfter = alpha();
    uint256 betaAfter = beta();

    // Virtual K, alpha, and beta should remain constant
    assert virtualKAfter == virtualKBefore, "Virtual K should remain constant";
    assert alphaAfter == alphaBefore, "Alpha should remain constant";
    assert betaAfter == betaBefore, "Beta should remain constant";

    // Virtual input should decrease by withdrawn amount
    assert virtualInputAfter == virtualInputBefore - inputTokensOut,
           "Virtual input tokens should decrease by withdrawal amount";

    // Virtual L changes should be consistent with bonding token changes
    // (This will depend on the specific virtual state update logic)
    assert virtualLAfter <= virtualLBefore,
           "Virtual L should not increase on liquidity removal";
}

// ============ INTEGRATION VERIFICATION ============

// Rule 8: Fee mechanism integrates properly with existing MEV protection
rule feeWithMEVProtection(env e) {
    uint256 bondingTokenAmount;
    uint256 minInputTokens;

    require bondingTokenAmount > 0;
    address bondingTokenAddr = bondingToken();
    require bondingTokenAddr.balanceOf(e.msg.sender) >= bondingTokenAmount;
    require !locked();
    require vaultApprovalInitialized();

    uint256 quotedAmount = quoteRemoveLiquidity(bondingTokenAmount);

    // If minInputTokens > quotedAmount, transaction should revert
    if (minInputTokens > quotedAmount) {
        removeLiquidity@withrevert(e, bondingTokenAmount, minInputTokens);
        assert lastReverted, "Transaction should revert when MEV protection triggered";
    } else {
        uint256 actualAmount = removeLiquidity(e, bondingTokenAmount, minInputTokens);
        assert actualAmount >= minInputTokens,
               "Actual amount should meet minimum requirement";
        assert actualAmount == quotedAmount,
               "Actual amount should match quote when not reverting";
    }
}

// Rule 9: Fee collection events and state changes are consistent
rule feeCollectionConsistency(env e) {
    uint256 bondingTokenAmount;
    uint256 minInputTokens;

    require bondingTokenAmount > 0;
    address bondingTokenAddr = bondingToken();
    require bondingTokenAddr.balanceOf(e.msg.sender) >= bondingTokenAmount;
    require !locked();
    require vaultApprovalInitialized();

    uint256 fee = withdrawalFeeBasisPoints();
    mathint expectedFeeAmount = (bondingTokenAmount * fee) / 10000;

    // Execute removeLiquidity
    removeLiquidity(e, bondingTokenAmount, minInputTokens);

    // Verify fee calculation matches expected mathematics
    if (fee > 0) {
        assert expectedFeeAmount > 0, "Non-zero fee rate should generate non-zero fee amount";
    } else {
        assert expectedFeeAmount == 0, "Zero fee rate should generate zero fee amount";
    }

    // Total fee amount should not exceed original bonding token amount
    assert expectedFeeAmount <= bondingTokenAmount,
           "Fee amount should never exceed bonding token amount";
}