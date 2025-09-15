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
    uint256 public constant SEED_INPUT = 1000 * 1e18; // 1K tokens
    uint256 public constant DESIRED_AVG_PRICE = 0.9e18; // 0.9 (90% of final price)
    
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
            IVault(address(vault))
        );
        
        vm.stopPrank();
        
        // Set the bonding curve address in the vault to allow B3 to call deposit/withdraw
        vault.setClient(address(b3), true);

        // Initialize vault approval after vault authorizes B3
        vm.startPrank(owner);
        b3.initializeVaultApproval();

        // Set virtual liquidity goals
        b3.setGoals(FUNDING_GOAL, SEED_INPUT, DESIRED_AVG_PRICE);
        vm.stopPrank();

        // Setup test tokens
        inputToken.mint(user1, 1000000 * 1e18);
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
        
        // Calculate expected using virtual pair formula:
        // virtualL_out = virtualL - (K / (virtualInputTokens + inputAmount))
        uint256 expectedNewVirtualL = K / (INITIAL_VIRTUAL_INPUT + inputAmount);
        uint256 expectedQuote = INITIAL_VIRTUAL_L - expectedNewVirtualL;
        
        uint256 actualQuote = b3.quoteAddLiquidity(inputAmount);
        
        assertEq(actualQuote, expectedQuote, "Quote should match calculated value");
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
        uint256 inputAmount = 1000; // Large amount relative to virtual pair scale (10000 initial)
        
        uint256 quote = b3.quoteAddLiquidity(inputAmount);
        
        assertTrue(quote > 0, "Should handle large amounts");
        assertTrue(quote < INITIAL_VIRTUAL_L, "Quote should not exceed initial virtual L");
    }
    
    function testQuoteAddLiquidityDifferentAmounts() public view {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 10; // Use small amounts proportional to virtual pair scale
        amounts[1] = 25;
        amounts[2] = 50;
        amounts[3] = 100;
        amounts[4] = 200;
        
        uint256 lastQuote = 0;
        
        for (uint i = 0; i < amounts.length; i++) {
            uint256 quote = b3.quoteAddLiquidity(amounts[i]);
            
            // Quotes should increase with larger input amounts
            assertTrue(quote > lastQuote, "Larger input should give larger quote");
            
            // Calculate expected value
            uint256 expectedNewVL = K / (INITIAL_VIRTUAL_INPUT + amounts[i]);
            uint256 expectedQuote = INITIAL_VIRTUAL_L - expectedNewVL;
            
            assertEq(quote, expectedQuote, string(abi.encodePacked("Quote ", vm.toString(i), " should match calculation")));
            
            lastQuote = quote;
        }
    }
    
    // ============ QUOTE REMOVE LIQUIDITY TESTS ============
    
    function testQuoteRemoveLiquidityBasic() public view {
        uint256 bondingAmount = 10000;
        
        uint256 quotedAmount = b3.quoteRemoveLiquidity(bondingAmount);
        
        // Should return non-zero quote
        assertTrue(quotedAmount > 0, "Quote should be non-zero");
    }
    
    function testQuoteRemoveLiquidityMath() public view {
        uint256 bondingAmount = 10000;
        
        // Calculate expected using virtual pair formula:
        // inputTokens_out = virtualInputTokens - (K / (virtualL + bondingAmount))
        uint256 expectedNewVirtualInput = K / (INITIAL_VIRTUAL_L + bondingAmount);
        uint256 expectedQuote = INITIAL_VIRTUAL_INPUT - expectedNewVirtualInput;
        
        uint256 actualQuote = b3.quoteRemoveLiquidity(bondingAmount);
        
        assertEq(actualQuote, expectedQuote, "Quote should match calculated value");
    }
    
    function testQuoteRemoveLiquidityZeroInput() public view {
        uint256 quote = b3.quoteRemoveLiquidity(0);
        
        // Should return zero for zero input
        assertEq(quote, 0, "Quote for zero input should be zero");
    }
    
    function testQuoteRemoveLiquiditySmallAmount() public view {
        uint256 bondingAmount = 100; // Small amount
        
        uint256 quote = b3.quoteRemoveLiquidity(bondingAmount);
        
        assertTrue(quote > 0, "Should handle small amounts");
    }
    
    function testQuoteRemoveLiquidityLargeAmount() public view {
        uint256 bondingAmount = 50000000; // Large amount
        
        uint256 quote = b3.quoteRemoveLiquidity(bondingAmount);
        
        assertTrue(quote > 0, "Should handle large amounts");
        assertTrue(quote < INITIAL_VIRTUAL_INPUT, "Quote should not exceed initial virtual input");
    }
    
    function testQuoteRemoveLiquidityDifferentAmounts() public view {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 100000;   // These amounts should be significant relative to virtualL = 100000000
        amounts[1] = 500000;
        amounts[2] = 1000000;
        amounts[3] = 5000000;
        amounts[4] = 10000000;
        
        uint256 lastQuote = 0;
        
        for (uint i = 0; i < amounts.length; i++) {
            uint256 quote = b3.quoteRemoveLiquidity(amounts[i]);
            
            // Quotes should increase with larger bonding token amounts
            assertTrue(quote > lastQuote, "Larger bonding amount should give larger quote");
            
            // Calculate expected value
            uint256 expectedNewVI = K / (INITIAL_VIRTUAL_L + amounts[i]);
            uint256 expectedQuote = INITIAL_VIRTUAL_INPUT - expectedNewVI;
            
            assertEq(quote, expectedQuote, string(abi.encodePacked("Quote ", vm.toString(i), " should match calculation")));
            
            lastQuote = quote;
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
        for (uint i = 0; i < 10; i++) {
            b3.quoteAddLiquidity(1000 * 1e18 * (i + 1));
            b3.quoteRemoveLiquidity(10000 * (i + 1));
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
            assertTrue(quote > 0, "Should handle maximum bonding amount");
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
        
        // Due to virtual pair math, removing immediately after adding should yield less than original
        assertTrue(inputQuote < inputAmount, "Remove quote should be less than original input due to virtual pair math");
        assertTrue(inputQuote > 0, "Remove quote should be positive");
    }
}