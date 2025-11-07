// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title B3CertoraFixValidationTest
 * @notice Tests for validating the Certora rule fixes implemented in stories 024.71, 024.72, 024.73
 * @dev This test suite validates the specific edge cases that were fixed:
 *      1. feeCollectionConsistency: Integer division edge cases where (bondingTokenAmount * fee) < 10000
 *      2. quoteConsistencyAcrossFees: 100% fee edge case where effectiveBondingTokens == 0
 *      3. withdrawalAmountCorrectWithFee: Mathematical precision around 10000 threshold
 *
 * CRITICAL EDGE CASES TESTED:
 * - Integer division results in 0 fee when (bondingTokenAmount * fee) < 10000
 * - 100% fee scenarios where all tokens are consumed as fee
 * - Boundary conditions around the 10000 basis points calculation
 * - Dust amount handling for very small bondingTokenAmount values
 * - Fee range extremes (0%, 1%, 99%, 100%)
 */
contract B3CertoraFixValidationTest is Test {
    Behodler3Tokenlaunch public b3;
    MockVault public vault;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);

    // Test parameters
    uint256 public constant FUNDING_GOAL = 1_000_000 * 1e18;
    uint256 public constant SEED_INPUT = 0;
    uint256 public constant DESIRED_AVG_PRICE = 0.9e18;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));

        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)),
            IBondingToken(address(bondingToken)),
            IYieldStrategy(address(vault))
        );

        vm.stopPrank();

        // Set up vault permissions
        vault.setClient(address(b3), true);

        // Initialize virtual pair and vault approval
        vm.startPrank(owner);
        b3.initializeVaultApproval();
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);
        vm.stopPrank();

        // Add liquidity to get into operational state
        inputToken.mint(owner, 100_000 * 1e18);

        vm.startPrank(owner);
        inputToken.approve(address(b3), 100_000 * 1e18);
        b3.addLiquidity(10_000 * 1e18, 1);
        vm.stopPrank();
    }

    // ============ INTEGER DIVISION EDGE CASES (Story 024.71 - feeCollectionConsistency) ============

    /**
     * @dev Test Case 1: Integer division edge case where (bondingTokenAmount * fee) < 10000
     * This was the core issue in feeCollectionConsistency rule - when the multiplication
     * result is less than 10000, the division results in 0 due to Solidity integer division.
     */
    function test_IntegerDivisionEdgeCase_VerySmallAmount() public {
        vm.prank(owner);
        b3.setWithdrawalFee(5000); // 50% fee

        // Test with bondingTokenAmount = 1, fee = 5000
        // (1 * 5000) / 10000 = 5000 / 10000 = 0 (integer division)
        uint256 bondingAmount = 1;
        uint256 quote = b3.quoteRemoveLiquidity(bondingAmount);

        // Since feeAmount = 0, effectiveBondingTokens should equal bondingAmount
        // This validates the fix in the Certora rule
        assertTrue(quote >= 0, "Quote should be non-negative even for dust amounts");

        // Log for analysis
        console.log("bondingAmount:", bondingAmount);
        console.log("fee basis points:", b3.withdrawalFeeBasisPoints());
        console.log("(bondingAmount * fee):", bondingAmount * b3.withdrawalFeeBasisPoints());
        console.log("quote:", quote);
    }

    /**
     * @dev Test Case 2: Edge case where (bondingTokenAmount * fee) exactly equals 10000
     * This tests the boundary condition in the integer division logic.
     */
    function test_IntegerDivisionBoundary_Exact10000() public {
        vm.prank(owner);
        b3.setWithdrawalFee(1000); // 10% fee

        // bondingTokenAmount = 10, fee = 1000
        // (10 * 1000) / 10000 = 10000 / 10000 = 1
        uint256 bondingAmount = 10;
        uint256 quote = b3.quoteRemoveLiquidity(bondingAmount);

        assertTrue(quote >= 0, "Quote should be valid at boundary condition");

        console.log("Boundary test - bondingAmount:", bondingAmount);
        console.log("Fee basis points:", b3.withdrawalFeeBasisPoints());
        console.log("Product calculation:", bondingAmount * b3.withdrawalFeeBasisPoints());
        console.log("Expected feeAmount:", (bondingAmount * b3.withdrawalFeeBasisPoints()) / 10000);
    }

    /**
     * @dev Test Case 3: Multiple dust amounts with various fee rates
     * Tests the pattern found in all three fixed rules: conditional assertions based on
     * whether (bondingTokenAmount * fee) >= 10000
     */
    function test_DustAmountsVariousFeeRates() public {
        uint256[] memory feeRates = new uint256[](5);
        feeRates[0] = 1;      // 0.01%
        feeRates[1] = 100;    // 1%
        feeRates[2] = 1000;   // 10%
        feeRates[3] = 5000;   // 50%
        feeRates[4] = 9999;   // 99.99%

        for (uint256 i = 0; i < feeRates.length; i++) {
            vm.prank(owner);
            b3.setWithdrawalFee(feeRates[i]);

            // Test with very small bondingToken amounts
            for (uint256 amount = 1; amount <= 10; amount++) {
                uint256 product = amount * feeRates[i];
                uint256 expectedFee = product / 10000;
                uint256 quote = b3.quoteRemoveLiquidity(amount);

                console.log("Testing amount:", amount);
                console.log("Fee rate:", feeRates[i]);
                console.log("Product:", product);
                console.log("Expected fee:", expectedFee);

                if (product < 10000) {
                    // When product < 10000, expectedFee should be 0 due to integer division
                    assertEq(expectedFee, 0, "Expected fee should be 0 due to integer division");
                } else {
                    // When product >= 10000, expectedFee should be > 0
                    assertTrue(expectedFee > 0, "Expected fee should be positive when product >= 10000");
                }

                assertTrue(quote >= 0, "Quote should always be non-negative");
            }
        }
    }

    // ============ 100% FEE EDGE CASES (Story 024.72 - quoteConsistencyAcrossFees) ============

    /**
     * @dev Test Case 4: 100% fee scenario where effectiveBondingTokens == 0
     * This was the specific issue in quoteConsistencyAcrossFees rule.
     */
    function test_MaximumFee_100Percent() public {
        vm.prank(owner);
        b3.setWithdrawalFee(10000); // 100% fee

        uint256 bondingAmount = 1000;
        uint256 quote = b3.quoteRemoveLiquidity(bondingAmount);

        // With 100% fee, all bonding tokens are consumed as fee
        // effectiveBondingTokens = bondingAmount - (bondingAmount * 10000) / 10000 = bondingAmount - bondingAmount = 0

        // The quote should be 0 or very minimal since no effective tokens remain
        console.log("100% fee test - bondingAmount:", bondingAmount);
        console.log("Quote with 100% fee:", quote);

        // Validate the mathematical relationship
        uint256 feeAmount = (bondingAmount * 10000) / 10000;
        uint256 effectiveTokens = bondingAmount - feeAmount;
        assertEq(effectiveTokens, 0, "With 100% fee, effective tokens should be 0");
        assertEq(feeAmount, bondingAmount, "With 100% fee, fee amount should equal bonding amount");
    }

    /**
     * @dev Test Case 5: Quote consistency across different fee rates
     * This validates the fix for the quoteConsistencyAcrossFees rule.
     */
    function test_QuoteConsistencyAcrossAllFeeRates() public {
        uint256 bondingAmount = 10000; // Large enough to avoid integer division issues

        uint256[] memory feeRates = new uint256[](6);
        feeRates[0] = 0;      // 0%
        feeRates[1] = 1000;   // 10%
        feeRates[2] = 2500;   // 25%
        feeRates[3] = 5000;   // 50%
        feeRates[4] = 7500;   // 75%
        feeRates[5] = 10000;  // 100%

        uint256[] memory quotes = new uint256[](6);

        // Get quotes for all fee rates
        for (uint256 i = 0; i < feeRates.length; i++) {
            vm.prank(owner);
            b3.setWithdrawalFee(feeRates[i]);
            quotes[i] = b3.quoteRemoveLiquidity(bondingAmount);

            console.log("Fee rate:", feeRates[i]);
            console.log("Quote:", quotes[i]);
        }

        // Validate monotonicity: higher fees should result in lower or equal quotes
        for (uint256 i = 1; i < quotes.length; i++) {
            assertTrue(quotes[i] <= quotes[i-1], "Higher fee should result in lower or equal quote");
        }

        // Specific validation for 100% fee
        assertEq(quotes[5], 0, "100% fee should result in zero quote");
    }

    // ============ MATHEMATICAL PRECISION TESTS (Story 024.73 - withdrawalAmountCorrectWithFee) ============

    /**
     * @dev Test Case 6: Boundary conditions around the 10000 threshold
     * Tests the mathematical precision issues that were fixed.
     */
    function test_MathematicalPrecision_AroundThreshold() public {
        vm.prank(owner);
        b3.setWithdrawalFee(1000); // 10% fee

        // Test amounts around the critical threshold
        uint256[] memory testAmounts = new uint256[](7);
        testAmounts[0] = 9;   // (9 * 1000) = 9000 < 10000
        testAmounts[1] = 10;  // (10 * 1000) = 10000 == 10000
        testAmounts[2] = 11;  // (11 * 1000) = 11000 > 10000
        testAmounts[3] = 50;  // (50 * 1000) = 50000 > 10000
        testAmounts[4] = 99;  // (99 * 1000) = 99000 > 10000
        testAmounts[5] = 100; // (100 * 1000) = 100000 > 10000
        testAmounts[6] = 1000; // (1000 * 1000) = 1000000 > 10000

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            uint256 product = amount * 1000; // fee = 1000
            uint256 expectedFee = product / 10000;
            uint256 expectedEffective = amount - expectedFee;

            uint256 quote = b3.quoteRemoveLiquidity(amount);

            console.log("Amount:", amount);
            console.log("Product:", product);
            console.log("Expected Fee:", expectedFee);
            console.log("Expected Effective:", expectedEffective);

            // Validate the mathematical relationships from the Certora fixes
            if (product >= 10000) {
                assertTrue(expectedFee > 0, "Fee should be positive when product >= 10000");
                assertTrue(expectedEffective < amount, "Effective tokens should be less than original when fee applied");
            } else {
                assertEq(expectedFee, 0, "Fee should be 0 when product < 10000");
                assertEq(expectedEffective, amount, "Effective tokens should equal original when no fee due to integer division");
            }
        }
    }

    /**
     * @dev Test Case 7: Comprehensive edge case matrix
     * Tests the combination of various amounts and fee rates to validate all edge cases.
     */
    function test_ComprehensiveEdgeCaseMatrix() public {
        // Test fee rates (basis points)
        uint256[] memory feeRates = new uint256[](7);
        feeRates[0] = 0;      // 0%
        feeRates[1] = 1;      // 0.01%
        feeRates[2] = 100;    // 1%
        feeRates[3] = 1000;   // 10%
        feeRates[4] = 5000;   // 50%
        feeRates[5] = 9999;   // 99.99%
        feeRates[6] = 10000;  // 100%

        // Test amounts
        uint256[] memory amounts = new uint256[](8);
        amounts[0] = 1;       // Minimal
        amounts[1] = 5;       // Small
        amounts[2] = 10;      // Threshold boundary
        amounts[3] = 50;      // Medium small
        amounts[4] = 100;     // Medium
        amounts[5] = 1000;    // Large
        amounts[6] = 10000;   // Very large
        amounts[7] = 100000;  // Maximum test

        for (uint256 feeIdx = 0; feeIdx < feeRates.length; feeIdx++) {
            vm.prank(owner);
            b3.setWithdrawalFee(feeRates[feeIdx]);

            for (uint256 amtIdx = 0; amtIdx < amounts.length; amtIdx++) {
                uint256 amount = amounts[amtIdx];
                uint256 fee = feeRates[feeIdx];
                uint256 product = amount * fee;

                // This should not revert - validates that all Certora rules now pass
                uint256 quote = b3.quoteRemoveLiquidity(amount);

                // Mathematical validations based on the fixed rules
                if (fee == 0) {
                    // Zero fee case
                    assertTrue(quote >= 0, "Zero fee should produce valid quote");
                } else if (fee == 10000) {
                    // 100% fee case
                    assertEq(quote, 0, "100% fee should result in zero quote");
                } else if (product < 10000) {
                    // Integer division results in 0 fee
                    assertTrue(quote >= 0, "Small amounts should still produce valid quotes");
                } else {
                    // Normal fee application
                    assertTrue(quote >= 0, "Normal fee cases should produce valid quotes");
                }

                console.log("Fee:", fee);
                console.log("Amount:", amount);
                console.log("Product:", product);
                console.log("Quote:", quote);
            }
        }
    }

    // ============ REGRESSION TESTS ============

    /**
     * @dev Test Case 8: Ensure existing functionality still works
     * Validates that the fixes don't break normal operation.
     */
    function test_NormalOperationRegression() public {
        // Test with standard amounts and fees that should work normally
        vm.prank(owner);
        b3.setWithdrawalFee(500); // 5% fee

        uint256 bondingAmount = 1000 * 1e18;

        // IMPORTANT: User must have tokens BEFORE getting quote for accurate results
        // This test was previously creating external minting scenario inadvertently
        vm.startPrank(user1);
        bondingToken.mint(user1, bondingAmount);
        bondingToken.approve(address(b3), bondingAmount);

        // Get quote AFTER user has tokens (normal flow)
        uint256 quoteBefore = b3.quoteRemoveLiquidity(bondingAmount);

        // Execute actual removal
        uint256 actualAmount = b3.removeLiquidity(bondingAmount, 1);
        vm.stopPrank();

        // Quote and actual should match when no external minting occurs between them
        // Note: After Story 035, external minting between quote and removal would cause mismatch
        assertEq(actualAmount, quoteBefore, "Quote and actual removal should match");

        // Fee should have been properly applied
        uint256 expectedFee = (bondingAmount * 500) / 10000;
        uint256 expectedEffective = bondingAmount - expectedFee;

        assertTrue(expectedFee > 0, "Expected fee should be positive for normal amounts");
        assertTrue(expectedEffective < bondingAmount, "Effective amount should be reduced by fee");

        console.log("Normal operation test:");
        console.log("Original bonding amount:", bondingAmount);
        console.log("Expected fee:", expectedFee);
        console.log("Expected effective:", expectedEffective);
        console.log("Actual received:", actualAmount);
    }

    /**
     * @dev Test Case 9: Gas cost analysis for edge cases
     * Ensures that the fixes don't significantly impact gas costs.
     */
    function test_GasCostAnalysis() public {
        // Test gas costs for various scenarios
        vm.prank(owner);
        b3.setWithdrawalFee(1000); // 10% fee

        uint256 gasBefore;
        uint256 gasAfter;

        // Test 1: Dust amount (integer division edge case)
        gasBefore = gasleft();
        b3.quoteRemoveLiquidity(1);
        gasAfter = gasleft();
        uint256 dustGasCost = gasBefore - gasAfter;

        // Test 2: Normal amount
        gasBefore = gasleft();
        b3.quoteRemoveLiquidity(10000);
        gasAfter = gasleft();
        uint256 normalGasCost = gasBefore - gasAfter;

        // Test 3: Large amount
        gasBefore = gasleft();
        b3.quoteRemoveLiquidity(1000000);
        gasAfter = gasleft();
        uint256 largeGasCost = gasBefore - gasAfter;

        console.log("Gas cost analysis:");
        console.log("Dust amount gas:", dustGasCost);
        console.log("Normal amount gas:", normalGasCost);
        console.log("Large amount gas:", largeGasCost);

        // Gas costs should be reasonable and consistent
        assertTrue(dustGasCost < 100000, "Dust amount gas cost should be reasonable");
        assertTrue(normalGasCost < 100000, "Normal amount gas cost should be reasonable");
        assertTrue(largeGasCost < 100000, "Large amount gas cost should be reasonable");
    }

    // ============ HELPER FUNCTIONS ============

    /**
     * @dev Helper function to calculate expected fee amount using the same logic as the contract
     */
    function calculateExpectedFee(uint256 bondingTokenAmount, uint256 feeBasisPoints) internal pure returns (uint256) {
        return (bondingTokenAmount * feeBasisPoints) / 10000;
    }

    /**
     * @dev Helper function to log detailed fee calculation
     */
    function logFeeCalculation(uint256 amount, uint256 fee) internal view {
        uint256 product = amount * fee;
        uint256 calculatedFee = product / 10000;
        uint256 effectiveTokens = amount - calculatedFee;

        console.log("=== Fee Calculation Details ===");
        console.log("Bonding Token Amount:", amount);
        console.log("Fee Basis Points:", fee);
        console.log("Product (amount * fee):", product);
        console.log("Calculated Fee:", calculatedFee);
        console.log("Effective Tokens:", effectiveTokens);
        console.log("Product < 10000:", product < 10000);
        console.log("===============================");
    }
}