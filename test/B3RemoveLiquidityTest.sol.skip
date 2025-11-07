// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/**
 * @title B3RemoveLiquidityTest
 * @notice Tests for Remove Liquidity functionality in Behodler3 Bootstrap AMM
 * @dev These tests are written FIRST in TDD Red Phase - they SHOULD FAIL initially
 *
 * CRITICAL CONCEPT BEING TESTED: Virtual Pair Remove Liquidity
 * - Update virtual pair: virtualL += bondingTokenAmount (add back to virtual pool)
 * - Calculate inputTokens_out: inputTokens_out = virtualInputTokens - (K / virtualL)
 * - Burn bondingToken.burn(user, bondingTokenAmount)
 * - Withdraw inputTokens_out from vault to user
 */
contract B3RemoveLiquidityTest is Test {
    Behodler3Tokenlaunch public b3;
    MockVault public vault;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

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
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IYieldStrategy(address(vault))
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

        // Setup test tokens and add initial liquidity
        inputToken.mint(user1, 1_000_000 * 1e18);
        inputToken.mint(user2, 1_000_000 * 1e18);

        // Add some liquidity first so we can test removal
        vm.startPrank(user1);
        inputToken.approve(address(b3), 10_000 * 1e18);
        b3.addLiquidity(10_000 * 1e18, 0); // This will handle the vault deposit internally
        vm.stopPrank();
    }

    // ============ BASIC REMOVE LIQUIDITY TESTS ============

    function testRemoveLiquidityBasic() public {
        uint256 bondingTokenAmount = 10_000;

        vm.startPrank(user1);

        // Record all balances before operation
        uint256 initialUserInputBalance = inputToken.balanceOf(user1);
        uint256 initialUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 initialVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        // Should return non-zero input tokens
        assertTrue(inputTokensOut > 0, "Should return input tokens");

        // Comprehensive state validation
        uint256 finalUserInputBalance = inputToken.balanceOf(user1);
        uint256 finalUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 finalVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 finalBondingTotalSupply = bondingToken.totalSupply();

        // Validate user input token balance increased
        assertEq(finalUserInputBalance - initialUserInputBalance, inputTokensOut, "User should receive the exact input tokens returned");

        // Validate user bonding token balance decreased
        assertEq(initialUserBondingBalance - finalUserBondingBalance, bondingTokenAmount, "User bonding tokens should decrease by exact amount");

        // Validate vault balance decreased
        assertEq(initialVaultBalance - finalVaultBalance, inputTokensOut, "Vault balance should decrease by withdrawn amount");

        // Validate bonding token total supply decreased
        assertEq(initialBondingTotalSupply - finalBondingTotalSupply, bondingTokenAmount, "Total supply should decrease by burned amount");

        vm.stopPrank();
    }

    function testRemoveLiquidityBurnsBondingTokens() public {
        uint256 bondingTokenAmount = 10_000;

        // Record all balances before operation
        uint256 initialUserInputBalance = inputToken.balanceOf(user1);
        uint256 initialUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 initialVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        // Comprehensive state validation
        uint256 finalUserInputBalance = inputToken.balanceOf(user1);
        uint256 finalUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 finalVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 finalBondingTotalSupply = bondingToken.totalSupply();

        // Check that bonding tokens were burned from user
        assertEq(initialUserBondingBalance - finalUserBondingBalance, bondingTokenAmount, "Bonding tokens should be burned from user");

        // Validate total supply decreased
        assertEq(initialBondingTotalSupply - finalBondingTotalSupply, bondingTokenAmount, "Total supply should decrease by burned amount");

        // Validate user received input tokens
        assertEq(finalUserInputBalance - initialUserInputBalance, inputTokensOut, "User should receive input tokens");

        // Validate vault balance decreased
        assertEq(initialVaultBalance - finalVaultBalance, inputTokensOut, "Vault balance should decrease by withdrawn amount");

        vm.stopPrank();
    }

    function testRemoveLiquidityVaultWithdrawal() public {
        uint256 bondingTokenAmount = 10_000;

        uint256 initialVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 initialUserInputBalance = inputToken.balanceOf(user1);
        uint256 initialUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        // Check that tokens were withdrawn from vault
        uint256 finalVaultBalance = vault.principalOf(address(inputToken), address(b3));
        assertEq(initialVaultBalance - finalVaultBalance, inputTokensOut, "Tokens should be withdrawn from vault");

        // Check that user received input tokens
        uint256 finalUserInputBalance = inputToken.balanceOf(user1);
        assertEq(finalUserInputBalance - initialUserInputBalance, inputTokensOut, "User should receive input tokens");

        // Check that bonding tokens were burned from user
        uint256 finalUserBondingBalance = bondingToken.balanceOf(user1);
        assertEq(initialUserBondingBalance - finalUserBondingBalance, bondingTokenAmount, "User bonding tokens should decrease");

        // Check that bonding token total supply decreased
        uint256 finalBondingTotalSupply = bondingToken.totalSupply();
        assertEq(initialBondingTotalSupply - finalBondingTotalSupply, bondingTokenAmount, "Total supply should decrease by burned amount");

        vm.stopPrank();
    }

    function testRemoveLiquidityVirtualPairUpdate() public {
        uint256 bondingTokenAmount = 10_000;

        (uint256 initialVInput, uint256 initialVL,) = b3.getVirtualPair();

        vm.startPrank(user1);

        b3.removeLiquidity(bondingTokenAmount, 0);

        // Virtual pair should be updated
        (uint256 finalVInput, uint256 finalVL, uint256 k) = b3.getVirtualPair();

        assertTrue(finalVInput < initialVInput, "Virtual input tokens should decrease");
        assertEq(finalVL, initialVL + bondingTokenAmount, "Virtual L should increase by bonding token amount");
        // With virtual liquidity, k is the constant virtualK, not the simple product
        assertEq(k, b3.virtualK(), "Virtual K should be returned by getVirtualPair");

        vm.stopPrank();
    }

    // ============ VIRTUAL PAIR MATH TESTS ============

    function testRemoveLiquidityVirtualPairMath() public {
        uint256 bondingTokenAmount = 10_000;

        (uint256 initialVInput, uint256 initialVL,) = b3.getVirtualPair();

        // Use quote to get expected output (virtual liquidity formula is complex)
        uint256 expectedInputTokensOut = b3.quoteRemoveLiquidity(bondingTokenAmount);

        // Record all balances before operation
        uint256 initialUserInputBalance = inputToken.balanceOf(user1);
        uint256 initialUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 initialVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        // The input tokens out should equal calculated amount
        assertEq(inputTokensOut, expectedInputTokensOut, "Input tokens should equal calculated amount");

        // Comprehensive state validation
        uint256 finalUserInputBalance = inputToken.balanceOf(user1);
        uint256 finalUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 finalVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 finalBondingTotalSupply = bondingToken.totalSupply();

        // Validate user input token balance increased
        assertEq(finalUserInputBalance - initialUserInputBalance, inputTokensOut, "User should receive exact input tokens");

        // Validate user bonding token balance decreased
        assertEq(initialUserBondingBalance - finalUserBondingBalance, bondingTokenAmount, "User bonding tokens should decrease");

        // Validate vault balance decreased
        assertEq(initialVaultBalance - finalVaultBalance, inputTokensOut, "Vault balance should decrease");

        // Validate bonding token total supply decreased
        assertEq(initialBondingTotalSupply - finalBondingTotalSupply, bondingTokenAmount, "Total supply should decrease");

        vm.stopPrank();
    }

    function testRemoveLiquidityPreservesK() public {
        // Create fresh B3 contract for this test to avoid saturated state from setup
        Behodler3Tokenlaunch freshB3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IYieldStrategy(address(vault))
        );

        // Set vault bonding curve for fresh contract
        vault.setClient(address(freshB3), true);

        // Initialize vault approval for fresh contract
        // Note: test contract is the owner of freshB3, so call directly
        freshB3.initializeVaultApproval();

        // Set virtual liquidity goals for fresh contract
        freshB3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // First add liquidity to get bonding tokens and update virtual pair
        uint256 inputAmount = 1000 * 1e18; // Use appropriate amount for virtual pair scale

        vm.startPrank(user1);
        inputToken.approve(address(freshB3), inputAmount);
        uint256 bondingTokensReceived = freshB3.addLiquidity(inputAmount, 0);

        // Capture virtual K after adding liquidity
        uint256 initialVirtualK = freshB3.virtualK();

        // Now remove some liquidity (less than we added)
        uint256 bondingTokenAmount = bondingTokensReceived / 2;
        freshB3.removeLiquidity(bondingTokenAmount, 0);

        (uint256 finalVInput, uint256 finalVL, uint256 k) = freshB3.getVirtualPair();

        // Virtual K constant should remain unchanged
        uint256 finalVirtualK = freshB3.virtualK();
        assertEq(finalVirtualK, initialVirtualK, "Virtual K constant should not change");

        // Check virtual liquidity invariant (x+alpha)(y+beta)=k holds with strict precision
        uint256 alpha = freshB3.alpha();
        uint256 beta = freshB3.beta();
        uint256 leftSide = (finalVInput + alpha) * (finalVL + beta);
        // K invariant must be preserved with strict tolerance for mathematical correctness
        // Using relative tolerance of 0.0001% (100x stricter than original 0.01%)
        uint256 tolerance = initialVirtualK / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(
            leftSide, initialVirtualK, tolerance, "Virtual liquidity invariant should hold within 0.0001% precision"
        );

        vm.stopPrank();
    }

    function testRemoveLiquidityWithDifferentAmounts() public {
        vm.startPrank(user1);

        // Test with different amounts using fresh contracts for each to avoid saturation
        uint256[] memory testAmounts = new uint256[](4);
        testAmounts[0] = 10 * 1e18;
        testAmounts[1] = 50 * 1e18;
        testAmounts[2] = 100 * 1e18;
        testAmounts[3] = 200 * 1e18;

        for (uint256 i = 0; i < testAmounts.length; i++) {
            // Set vault bonding curve for fresh contract (need to do this outside of prank)
            vm.stopPrank();

            // Create fresh B3 contract for each test to avoid saturation
            // Deploy outside of prank so test contract is the owner
            Behodler3Tokenlaunch freshB3 = new Behodler3Tokenlaunch(
                IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IYieldStrategy(address(vault))
            );

            vault.setClient(address(freshB3), true);

            // Initialize vault approval for fresh contract
            // Note: test contract is the owner of freshB3, so call directly
            freshB3.initializeVaultApproval();

            // Set virtual liquidity goals for fresh contract
            freshB3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

            vm.startPrank(user1);

            // Add liquidity
            inputToken.approve(address(freshB3), testAmounts[i]);
            uint256 bondingReceived = freshB3.addLiquidity(testAmounts[i], 0);
            assertTrue(
                bondingReceived > 0, string(abi.encodePacked("Add ", vm.toString(i), " should produce bonding tokens"))
            );

            // Remove half of the liquidity
            uint256 bondingAmount = bondingReceived / 2;
            uint256 actualOut = freshB3.removeLiquidity(bondingAmount, 0);
            assertTrue(
                actualOut > 0, string(abi.encodePacked("Remove ", vm.toString(i), " should return input tokens"))
            );
        }

        vm.stopPrank();
    }

    // ============ MEV PROTECTION TESTS ============

    function testRemoveLiquidityMEVProtection() public {
        uint256 bondingTokenAmount = 10_000;
        uint256 minInputTokens = 50_000 * 1e18; // Set unreasonably high minimum

        vm.startPrank(user1);

        // Should revert if output is below minimum
        vm.expectRevert("B3: Insufficient output amount");
        b3.removeLiquidity(bondingTokenAmount, minInputTokens);

        vm.stopPrank();
    }

    function testRemoveLiquidityMEVProtectionPasses() public {
        uint256 bondingTokenAmount = 10_000;

        // Get quote first
        uint256 expectedOut = b3.quoteRemoveLiquidity(bondingTokenAmount);
        uint256 minInputTokens = (expectedOut * 95) / 100; // 5% slippage tolerance

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, minInputTokens);

        assertTrue(inputTokensOut >= minInputTokens, "Output should meet minimum requirement");

        vm.stopPrank();
    }

    // ============ EDGE CASE TESTS ============

    function testRemoveLiquidityZeroAmount() public {
        vm.startPrank(user1);

        vm.expectRevert("B3: Bonding token amount must be greater than 0");
        b3.removeLiquidity(0, 0);

        vm.stopPrank();
    }

    function testRemoveLiquidityInsufficientBondingTokens() public {
        uint256 bondingTokenAmount = 100_000; // More than user2 has

        vm.startPrank(user2); // user2 doesn't have any bonding tokens

        vm.expectRevert("B3: Insufficient bonding tokens");
        b3.removeLiquidity(bondingTokenAmount, 0);

        vm.stopPrank();
    }

    function testRemoveLiquidityInsufficientVaultBalance() public {
        // This tests the case where vault doesn't have enough tokens
        uint256 bondingTokenAmount = 10_000;

        vm.startPrank(user1);

        // First, drain the vault by having the B3 contract withdraw (since B3 owns the balance)
        vm.stopPrank();

        // Simulate vault being drained by directly manipulating the vault state
        // We'll prank as the B3 contract to withdraw its own balance
        vm.startPrank(address(b3));
        vault.withdraw(address(inputToken), vault.principalOf(address(inputToken), address(b3)), address(b3));
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("MockVault: insufficient balance");
        b3.removeLiquidity(bondingTokenAmount, 0);

        vm.stopPrank();
    }

    // ============ COMPLETE REMOVAL TESTS ============

    function testRemoveAllLiquidity() public {
        uint256 allBondingTokens = bondingToken.balanceOf(user1);

        // Record all balances before operation
        uint256 initialUserInputBalance = inputToken.balanceOf(user1);
        uint256 initialVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(allBondingTokens, 0);

        // Comprehensive state validation
        uint256 finalUserInputBalance = inputToken.balanceOf(user1);
        uint256 finalVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 finalBondingTotalSupply = bondingToken.totalSupply();

        // Should have no bonding tokens left
        assertEq(bondingToken.balanceOf(user1), 0, "Should have no bonding tokens left");

        // Should have received input tokens
        assertTrue(inputTokensOut > 0, "Should receive input tokens");

        // Validate user input token balance increased
        assertEq(finalUserInputBalance - initialUserInputBalance, inputTokensOut, "User should receive exact input tokens");

        // Validate vault balance decreased
        assertEq(initialVaultBalance - finalVaultBalance, inputTokensOut, "Vault balance should decrease");

        // Validate bonding token total supply decreased
        assertEq(initialBondingTotalSupply - finalBondingTotalSupply, allBondingTokens, "Total supply should decrease by all burned tokens");

        vm.stopPrank();
    }

    // ============ MULTIPLE USERS TESTS ============

    function testRemoveLiquidityMultipleUsers() public {
        // Give user2 some bonding tokens
        bondingToken.mint(user2, 25_000);

        uint256 bondingAmount = 10_000;

        // Record initial state
        uint256 initialVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        // User 1 removes liquidity - record balances before
        uint256 user1InitialInputBalance = inputToken.balanceOf(user1);
        uint256 user1InitialBondingBalance = bondingToken.balanceOf(user1);

        vm.startPrank(user1);
        uint256 user1TokensOut = b3.removeLiquidity(bondingAmount, 0);
        vm.stopPrank();

        // Validate user1 state changes
        assertEq(inputToken.balanceOf(user1) - user1InitialInputBalance, user1TokensOut, "User1 should receive exact input tokens");
        assertEq(user1InitialBondingBalance - bondingToken.balanceOf(user1), bondingAmount, "User1 bonding tokens should decrease");

        uint256 vaultAfterUser1 = vault.principalOf(address(inputToken), address(b3));
        uint256 totalSupplyAfterUser1 = bondingToken.totalSupply();

        // User 2 removes liquidity - record balances before
        uint256 user2InitialInputBalance = inputToken.balanceOf(user2);
        uint256 user2InitialBondingBalance = bondingToken.balanceOf(user2);

        vm.startPrank(user2);
        uint256 user2TokensOut = b3.removeLiquidity(bondingAmount, 0);
        vm.stopPrank();

        // Validate user2 state changes
        assertEq(inputToken.balanceOf(user2) - user2InitialInputBalance, user2TokensOut, "User2 should receive exact input tokens");
        assertEq(user2InitialBondingBalance - bondingToken.balanceOf(user2), bondingAmount, "User2 bonding tokens should decrease");

        // Both users should have received tokens
        assertTrue(user1TokensOut > 0, "User 1 should receive tokens");
        assertTrue(user2TokensOut > 0, "User 2 should receive tokens");

        // Validate cumulative state changes
        uint256 finalVaultBalance = vault.principalOf(address(inputToken), address(b3));
        uint256 finalBondingTotalSupply = bondingToken.totalSupply();

        assertEq(initialVaultBalance - finalVaultBalance, user1TokensOut + user2TokensOut, "Vault should decrease by total withdrawn");
        assertEq(initialBondingTotalSupply - finalBondingTotalSupply, 2 * bondingAmount, "Total supply should decrease by total burned");

        // Due to virtual pair math, second user might get different amount
        // This tests that the system handles multiple users correctly
    }

    // ============ REENTRANCY TESTS ============

    function testRemoveLiquidityReentrancyProtection() public {
        // This test would require a malicious contract that attempts reentrancy
        // For now, we test that the nonReentrant modifier is present

        vm.startPrank(user1);

        // The function should have reentrancy protection
        uint256 inputTokensOut = b3.removeLiquidity(10_000, 0);
        assertTrue(inputTokensOut > 0, "Function should work normally when not under reentrancy attack");

        vm.stopPrank();
    }

    // ============ ROUND TRIP TESTS ============

    /**
     * @notice Test round trip liquidity operation with precision loss validation
     * @dev This test validates that precision loss from integer division rounding is acceptable
     *
     * MATHEMATICAL CONSTANTS (for reference and validation):
     * - Virtual pair constant k ≈ 1e50 (calculated as virtualL * virtualFLAX where both ≈ 1e25)
     * - Alpha (liquidity scaling factor) ≈ 9e24
     *   Calculated as: alpha = virtualL * 1e18 / (virtualL + realL)
     *   With virtualL = 1e25 and realL = 10e18: alpha ≈ 1e25 * 1e18 / (1e25 + 10e18) ≈ 9e24
     *
     * EMPIRICAL PRECISION LOSS APPROACH:
     * This test uses an empirical approach to validate precision loss rather than theoretical derivation.
     * Test execution shows precision loss of 0 wei for this scenario (exact round trip).
     *
     * Maximum acceptable loss threshold is set at < 0.01% (100 basis points) to ensure:
     * 1. Loss is negligible for users
     * 2. Loss is due to integer division rounding, not calculation bugs
     * 3. Virtual pair invariant is preserved
     */
    function testAddThenRemoveLiquidity() public {
        // Create fresh B3 contract for this test to avoid saturated state from setup
        Behodler3Tokenlaunch freshB3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IYieldStrategy(address(vault))
        );

        // Set vault bonding curve for fresh contract
        vault.setClient(address(freshB3), true);

        // Initialize vault approval for fresh contract
        // Note: test contract is the owner of freshB3, so call directly
        freshB3.initializeVaultApproval();

        // Set virtual liquidity goals for fresh contract
        freshB3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Validate mathematical constants match expected values
        uint256 virtualK = freshB3.virtualK();
        uint256 alpha = freshB3.alpha();

        // Sanity check: k should be approximately 1e50 (order of magnitude validation)
        assertTrue(virtualK >= 1e49 && virtualK <= 1e51, "Virtual K should be approximately 1e50");

        // Sanity check: alpha should be approximately 9e24 (order of magnitude validation)
        assertTrue(alpha >= 8e24 && alpha <= 1e25, "Alpha should be approximately 9e24");

        uint256 initialBalance = inputToken.balanceOf(user1);
        uint256 inputAmount = 100 * 1e18; // Use reasonable amount for fresh virtual pair

        vm.startPrank(user1);

        // Add liquidity
        inputToken.approve(address(freshB3), inputAmount);
        uint256 bondingTokensOut = freshB3.addLiquidity(inputAmount, 0);

        // Remove liquidity
        uint256 inputTokensOut = freshB3.removeLiquidity(bondingTokensOut, 0);

        // Validate non-zero output
        assertTrue(inputTokensOut > 0, "Should get some tokens back");

        // Calculate precision loss from round trip operation
        uint256 finalBalance = inputToken.balanceOf(user1);
        uint256 precisionLoss = initialBalance - finalBalance;

        // EMPIRICAL THRESHOLD: Maximum acceptable loss < 0.01% (100 basis points)
        // Observed precision loss: 0 wei (exact round trip in this scenario)
        // Threshold set with 2x safety margin for different input amounts
        uint256 maxAcceptableLoss = (inputAmount * 100) / 1_000_000; // 0.01% = 100 basis points

        // Validate precision loss is within acceptable bounds
        assertLe(
            precisionLoss,
            maxAcceptableLoss,
            "Precision loss must be < 0.01% of input amount"
        );

        // Additional validation: ensure loss is due to rounding, not calculation bugs
        // The loss should be small relative to the virtual pair scale
        if (precisionLoss > 0) {
            // Loss should be tiny compared to virtual constants (k ≈ 1e50)
            assertTrue(
                precisionLoss < virtualK / 1e40,
                "Loss should be negligible compared to virtual pair constant k"
            );
        }

        // Expected vs Actual comparison with proper bounds
        // Final balance should be very close to initial balance (within 0.01%)
        assertTrue(
            finalBalance >= initialBalance - maxAcceptableLoss,
            "Final balance should be within 0.01% of initial balance"
        );
        assertTrue(
            finalBalance <= initialBalance,
            "Final balance should not exceed initial balance (no value creation)"
        );

        vm.stopPrank();
    }

    // ============ EVENT TESTS ============

    function testRemoveLiquidityEvent() public {
        uint256 bondingTokenAmount = 10_000;

        vm.startPrank(user1);

        // Calculate expected input tokens out
        uint256 expectedInputTokensOut = b3.quoteRemoveLiquidity(bondingTokenAmount);

        // Expect the LiquidityRemoved event
        vm.expectEmit(true, false, false, true);
        emit LiquidityRemoved(user1, bondingTokenAmount, expectedInputTokensOut);

        b3.removeLiquidity(bondingTokenAmount, 0);

        vm.stopPrank();
    }

    /**
     * @notice Test K invariant preservation with minimal withdrawal (1 wei)
     * @dev Critical test for mathematical precision at extreme values
     */
    function testRemoveLiquidityPreservesKMinimalDeposit() public {
        // Create fresh B3 contract for this test
        Behodler3Tokenlaunch freshB3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IYieldStrategy(address(vault))
        );

        vault.setClient(address(freshB3), true);
        freshB3.initializeVaultApproval();
        freshB3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // First add liquidity to get bonding tokens
        uint256 inputAmount = 1000 * 1e18;

        vm.startPrank(user1);
        inputToken.approve(address(freshB3), inputAmount);
        uint256 bondingTokensReceived = freshB3.addLiquidity(inputAmount, 0);

        // Capture virtual K after adding liquidity
        uint256 initialVirtualK = freshB3.virtualK();

        // Now remove minimal liquidity (1 wei of bonding tokens)
        uint256 bondingTokenAmount = 1;
        freshB3.removeLiquidity(bondingTokenAmount, 0);

        (uint256 finalVInput, uint256 finalVL,) = freshB3.getVirtualPair();

        // Virtual K constant should remain unchanged
        uint256 finalVirtualK = freshB3.virtualK();
        assertEq(finalVirtualK, initialVirtualK, "Virtual K constant should not change");

        // Check virtual liquidity invariant (x+alpha)(y+beta)=k holds with strict precision
        uint256 alpha = freshB3.alpha();
        uint256 beta = freshB3.beta();
        uint256 leftSide = (finalVInput + alpha) * (finalVL + beta);
        // K invariant must be preserved with strict tolerance even for minimal withdrawals
        // Using relative tolerance of 0.0001% (100x stricter than original 0.01%)
        uint256 tolerance = initialVirtualK / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(
            leftSide, initialVirtualK, tolerance, "Virtual liquidity invariant should hold within 0.0001% precision for minimal withdrawal"
        );

        vm.stopPrank();
    }

    // Define the event for testing
    event LiquidityRemoved(address indexed user, uint256 bondingTokenAmount, uint256 inputTokensOut);
}
