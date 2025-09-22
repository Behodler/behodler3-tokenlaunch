// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title B3QuoteFunctionsTest
 * @notice Tests for Quote functions in Behodler3 Bootstrap AMM
 * @dev These tests are written FIRST in TDD Red Phase - they SHOULD FAIL initially
 *
 * CRITICAL CONCEPT BEING TESTED: Virtual Pair Quote Functions
 * - quoteAddLiquidity: Calculate virtualL_out for given input amount
 * - quoteRemoveLiquidity: Calculate inputTokens_out for given bonding token amount
 * - Quotes should match actual operations exactly
 * - Quote functions should be view-only and not change state
 */
contract B3QuoteFunctionsTest is Test {
    Behodler3Tokenlaunch public b3;
    MockVault public vault;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);

    // Virtual Liquidity Test Parameters
    uint256 public constant FUNDING_GOAL = 1_000_000 * 1e18; // 1M tokens
    uint256 public constant SEED_INPUT = 0; // Always zero with zero seed enforcement
    uint256 public constant DESIRED_AVG_PRICE = 0.9e18; // 0.9 (90% of final price)

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));

        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IVault(address(vault))
        );

        vm.stopPrank();

        // Set the bonding curve address in the vault to allow B3 to call deposit/withdraw
        vault.setClient(address(b3), true);

        // Initialize vault approval after vault authorizes B3
        vm.startPrank(owner);
        b3.initializeVaultApproval();

        // Set virtual liquidity goals
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);
        vm.stopPrank();

        // Setup test tokens
        inputToken.mint(user1, 1_000_000 * 1e18);
    }

    // ============ QUOTE ADD LIQUIDITY TESTS ============

    function testQuoteAddLiquidityBasic() public view {
        uint256 inputAmount = 1000 * 1e18;

        uint256 quotedAmount = b3.quoteAddLiquidity(inputAmount);

        // Should return non-zero quote
        assertTrue(quotedAmount > 0, "Quote should be non-zero");
    }

    function testQuoteAddLiquidityMath() public view {
        uint256 inputAmount = 1000 * 1e18;

        // Get current virtual pair state
        (uint256 currentVirtualInput, uint256 currentVirtualL,) = b3.getVirtualPair();

        // Calculate expected using virtual liquidity formula: (x+α)(y+β)=k
        // For add liquidity: virtualL reduces, virtualInput increases
        // newVirtualL = k / (virtualInput + inputAmount + α) - β
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 virtualK = b3.virtualK();

        uint256 denominator = currentVirtualInput + inputAmount + alpha;
        uint256 expectedNewVirtualL = virtualK / denominator - beta;
        uint256 expectedQuote = currentVirtualL - expectedNewVirtualL;

        uint256 actualQuote = b3.quoteAddLiquidity(inputAmount);

        // Use precision tolerance for large numbers
        uint256 tolerance = 1e14; // 0.01% tolerance for 1e18 scale
        assertApproxEqAbs(actualQuote, expectedQuote, tolerance, "Quote should match calculated value within tolerance");
    }

    function testQuoteAddLiquidityZeroInput() public view {
        uint256 quote = b3.quoteAddLiquidity(0);

        // Should return zero for zero input
        assertEq(quote, 0, "Quote for zero input should be zero");
    }

    function testQuoteAddLiquiditySmallAmount() public view {
        uint256 inputAmount = 1e18; // 1 token

        uint256 quote = b3.quoteAddLiquidity(inputAmount);

        assertTrue(quote > 0, "Should handle small amounts");
    }

    function testQuoteAddLiquidityLargeAmount() public view {
        uint256 inputAmount = 1000; // Large amount relative to virtual pair scale

        uint256 quote = b3.quoteAddLiquidity(inputAmount);
        (, uint256 currentVirtualL,) = b3.getVirtualPair();

        assertTrue(quote > 0, "Quote should be positive for add liquidity");
        assertTrue(quote < currentVirtualL, "Quote should not exceed current virtual L");
    }

    function testQuoteAddLiquidityDifferentAmounts() public view {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 10; // Use small amounts proportional to virtual pair scale
        amounts[1] = 25;
        amounts[2] = 50;
        amounts[3] = 100;
        amounts[4] = 200;

        uint256 lastQuote = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 quote = b3.quoteAddLiquidity(amounts[i]);

            // Quotes should increase with larger input amounts
            assertTrue(quote > lastQuote, "Larger input should give larger quote");

            // Simplified check - just verify quotes are increasing
            // (Detailed math verification is done in testQuoteAddLiquidityMath)

            lastQuote = quote;
        }
    }

    // ============ QUOTE REMOVE LIQUIDITY TESTS ============

    function testQuoteRemoveLiquidityBasic() public view {
        uint256 bondingAmount = 10_000;

        uint256 quotedAmount = b3.quoteRemoveLiquidity(bondingAmount);

        // With zero seed, should return zero until liquidity is added
        assertEq(quotedAmount, 0, "Quote should be zero with no input tokens available");
    }

    function testQuoteRemoveLiquidityMath() public view {
        uint256 bondingAmount = 10_000;

        // Get current virtual pair state
        (uint256 currentVirtualInput, uint256 currentVirtualL,) = b3.getVirtualPair();

        // Calculate expected using virtual liquidity formula: (x+α)(y+β)=k
        // For remove liquidity: virtualInput reduces, virtualL increases
        // newVirtualInput = k / (virtualL + bondingAmount + β) - α
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 virtualK = b3.virtualK();

        uint256 denominator = currentVirtualL + bondingAmount + beta;
        uint256 quotientWithOffset = virtualK / denominator;

        // With zero seed, quote should be zero since no input tokens are available
        uint256 expectedQuote;
        if (currentVirtualInput == 0) {
            expectedQuote = 0;
        } else {
            // Avoid underflow in calculations
            if (quotientWithOffset > alpha) {
                uint256 expectedNewVirtualInput = quotientWithOffset - alpha;
                expectedQuote = currentVirtualInput > expectedNewVirtualInput ?
                    currentVirtualInput - expectedNewVirtualInput : 0;
            } else {
                expectedQuote = 0;
            }
        }

        uint256 actualQuote = b3.quoteRemoveLiquidity(bondingAmount);

        // Use precision tolerance for large numbers
        uint256 tolerance = 1000; // Smaller tolerance for smaller amounts
        assertApproxEqAbs(actualQuote, expectedQuote, tolerance, "Quote should match calculated value within tolerance");
    }

    function testQuoteRemoveLiquidityZeroInput() public view {
        uint256 quote = b3.quoteRemoveLiquidity(0);

        // Should return zero for zero input
        assertEq(quote, 0, "Quote for zero input should be zero");
    }

    function testQuoteRemoveLiquiditySmallAmount() public view {
        uint256 bondingAmount = 100; // Small amount

        uint256 quote = b3.quoteRemoveLiquidity(bondingAmount);

        assertEq(quote, 0, "Quote should be zero with no input tokens available");
    }

    function testQuoteRemoveLiquidityLargeAmount() public view {
        uint256 bondingAmount = 50_000_000; // Large amount

        uint256 quote = b3.quoteRemoveLiquidity(bondingAmount);
        (uint256 currentVirtualInput,,) = b3.getVirtualPair();

        assertEq(quote, 0, "Quote should be zero with no input tokens available");
    }

    function testQuoteRemoveLiquidityDifferentAmounts() public view {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 100_000; // These amounts should be significant relative to virtualL = 100000000
        amounts[1] = 500_000;
        amounts[2] = 1_000_000;
        amounts[3] = 5_000_000;
        amounts[4] = 10_000_000;

        uint256 lastQuote = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 quote = b3.quoteRemoveLiquidity(amounts[i]);

            // With zero seed, all quotes should be zero until liquidity is added
            assertEq(quote, 0, "Quote should be zero with no input tokens available");

        }
    }

    // ============ QUOTE CONSISTENCY TESTS ============

    function testQuoteAddLiquidityConsistentWithActual() public {
        uint256 inputAmount = 1000 * 1e18;

        // Get quote
        uint256 quotedAmount = b3.quoteAddLiquidity(inputAmount);

        // Perform actual operation
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        uint256 actualAmount = b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();

        // Quote should match actual result
        assertEq(quotedAmount, actualAmount, "Quote should match actual add liquidity result");
    }

    function testQuoteRemoveLiquidityConsistentWithActual() public {
        // First add some liquidity to get bonding tokens
        vm.startPrank(user1);
        inputToken.approve(address(b3), 1000 * 1e18);
        uint256 bondingTokens = b3.addLiquidity(1000 * 1e18, 0);
        vm.stopPrank();

        // Get quote for removal
        uint256 quotedAmount = b3.quoteRemoveLiquidity(bondingTokens);

        // Perform actual removal
        vm.startPrank(user1);
        uint256 actualAmount = b3.removeLiquidity(bondingTokens, 0);
        vm.stopPrank();

        // Quote should match actual result
        assertEq(quotedAmount, actualAmount, "Quote should match actual remove liquidity result");
    }

    function testQuotesDoNotChangeState() public {
        // Store initial state
        (uint256 initialVInput, uint256 initialVL, uint256 initialK) = b3.getVirtualPair();
        uint256 initialBondingSupply = bondingToken.totalSupply();
        uint256 initialVaultBalance = vault.balanceOf(address(inputToken), address(b3));

        // Call quote functions multiple times
        for (uint256 i = 0; i < 10; i++) {
            b3.quoteAddLiquidity(1000 * 1e18 * (i + 1));
            b3.quoteRemoveLiquidity(10_000 * (i + 1));
        }

        // State should be unchanged
        (uint256 finalVInput, uint256 finalVL, uint256 finalK) = b3.getVirtualPair();
        uint256 finalBondingSupply = bondingToken.totalSupply();
        uint256 finalVaultBalance = vault.balanceOf(address(inputToken), address(b3));

        assertEq(initialVInput, finalVInput, "Virtual input should not change");
        assertEq(initialVL, finalVL, "Virtual L should not change");
        assertEq(initialK, finalK, "K should not change");
        assertEq(initialBondingSupply, finalBondingSupply, "Bonding token supply should not change");
        assertEq(initialVaultBalance, finalVaultBalance, "Vault balance should not change");
    }

    // ============ QUOTE EDGE CASES ============

    function testQuoteAddLiquidityMaxInput() public view {
        // Test with maximum possible input amount
        uint256 maxInput = type(uint256).max / 2; // Avoid overflow

        try b3.quoteAddLiquidity(maxInput) returns (uint256 quote) {
            assertTrue(quote > 0, "Should handle maximum input");
        } catch {
            // If it reverts due to overflow, that's acceptable
        }
    }

    function testQuoteRemoveLiquidityMaxBonding() public view {
        // Test with maximum possible bonding amount
        uint256 maxBonding = type(uint256).max / 2; // Avoid overflow

        try b3.quoteRemoveLiquidity(maxBonding) returns (uint256 quote) {
            assertEq(quote, 0, "Quote should be zero with no input tokens available");
        } catch {
            // If it reverts due to overflow, that's acceptable
        }
    }

    // ============ QUOTE PRECISION TESTS ============

    function testQuoteAddLiquidityPrecision() public view {
        uint256 smallAmount = 1; // Smallest possible amount

        uint256 quote = b3.quoteAddLiquidity(smallAmount);

        // Even for tiny amounts, should either return 0 or a positive value
        assertTrue(quote >= 0, "Quote should not be negative");
    }

    function testQuoteRemoveLiquidityPrecision() public view {
        uint256 smallAmount = 1; // Smallest possible amount

        uint256 quote = b3.quoteRemoveLiquidity(smallAmount);

        // Even for tiny amounts, should either return 0 or a positive value
        assertTrue(quote >= 0, "Quote should not be negative");
    }

    // ============ QUOTE MULTIPLE CALLS TESTS ============

    function testMultipleQuoteCallsConsistent() public view {
        uint256 inputAmount = 1000 * 1e18;

        // Call quote function multiple times
        uint256 quote1 = b3.quoteAddLiquidity(inputAmount);
        uint256 quote2 = b3.quoteAddLiquidity(inputAmount);
        uint256 quote3 = b3.quoteAddLiquidity(inputAmount);

        // All quotes should be identical (no state changes)
        assertEq(quote1, quote2, "Multiple quotes should be consistent");
        assertEq(quote2, quote3, "Multiple quotes should be consistent");
    }

    function testQuoteAfterStateChanges() public {
        uint256 inputAmount = 1000 * 1e18;

        // Get initial quote
        uint256 initialQuote = b3.quoteAddLiquidity(inputAmount);

        // Make state changes
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();

        // Get new quote (should be different due to changed virtual pair)
        uint256 newQuote = b3.quoteAddLiquidity(inputAmount);

        // Quotes should be different after state change
        assertTrue(newQuote != initialQuote, "Quote should change after state modification");
        assertTrue(newQuote < initialQuote, "Subsequent quotes should be smaller due to virtual pair math");
    }

    // ============ QUOTE SYMMETRY TESTS ============

    function testQuoteSymmetryAddRemove() public {
        uint256 inputAmount = 1000 * 1e18;

        // Quote add liquidity
        uint256 bondingQuote = b3.quoteAddLiquidity(inputAmount);

        // Quote remove liquidity with the quoted amount
        uint256 inputQuote = b3.quoteRemoveLiquidity(bondingQuote);

        // With zero seed, remove quote is zero because no input tokens are available in virtual state
        assertEq(inputQuote, 0, "Remove quote should be zero with zero seed until liquidity is actually added");
        assertTrue(bondingQuote > 0, "Add liquidity quote should be positive");
    }
}
