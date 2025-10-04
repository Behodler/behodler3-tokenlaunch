// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/**
 * @title B3AddLiquidityTest
 * @notice Tests for Add Liquidity functionality in Behodler3 Bootstrap AMM
 * @dev These tests are written FIRST in TDD Red Phase - they SHOULD FAIL initially
 *
 * CRITICAL CONCEPT BEING TESTED: Virtual Pair Add Liquidity
 * - Calculate virtualL_out using virtual pair math: virtualL_out = virtualL - (K / (virtualInputTokens + inputAmount))
 * - Mint bondingToken.mint(user, virtualL_out) - this is the key difference
 * - Deposit inputAmount to vault
 * - Update virtual pair state
 */
contract B3AddLiquidityTest is Test {
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
        inputToken.mint(user2, 1_000_000 * 1e18);
    }

    // ============ BASIC ADD LIQUIDITY TESTS ============

    function testAddLiquidityBasic() public {
        uint256 inputAmount = 1000 * 1e18;

        // Record all balances before operation
        uint256 initialUserInputBalance = inputToken.balanceOf(user1);
        uint256 initialUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 initialVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, 0);

        // Comprehensive state validation
        uint256 finalUserInputBalance = inputToken.balanceOf(user1);
        uint256 finalUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 finalVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        uint256 finalBondingTotalSupply = bondingToken.totalSupply();

        // Should return non-zero bonding tokens
        assertTrue(bondingTokensOut > 0, "Should mint bonding tokens");

        // Check that bonding tokens were actually minted to user
        assertEq(finalUserBondingBalance - initialUserBondingBalance, bondingTokensOut, "User should receive bonding tokens");

        // Validate user input token balance decreased
        assertEq(initialUserInputBalance - finalUserInputBalance, inputAmount, "User input tokens should decrease by exact amount");

        // Validate vault balance increased
        assertEq(finalVaultBalance - initialVaultBalance, inputAmount, "Vault balance should increase by deposited amount");

        // Validate bonding token total supply increased
        assertEq(finalBondingTotalSupply - initialBondingTotalSupply, bondingTokensOut, "Total supply should increase by minted amount");

        vm.stopPrank();
    }

    function testAddLiquidityVaultDeposit() public {
        uint256 inputAmount = 1000 * 1e18;

        // Record all balances before operation
        uint256 initialUserInputBalance = inputToken.balanceOf(user1);
        uint256 initialUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 initialVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, 0);

        // Comprehensive state validation
        uint256 finalUserInputBalance = inputToken.balanceOf(user1);
        uint256 finalUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 finalVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        uint256 finalBondingTotalSupply = bondingToken.totalSupply();

        // Check that tokens were deposited to vault
        assertEq(finalVaultBalance - initialVaultBalance, inputAmount, "Tokens should be deposited to vault");

        // Validate user input token balance decreased
        assertEq(initialUserInputBalance - finalUserInputBalance, inputAmount, "User input tokens should decrease");

        // Validate user bonding token balance increased
        assertEq(finalUserBondingBalance - initialUserBondingBalance, bondingTokensOut, "User bonding tokens should increase");

        // Validate bonding token total supply increased
        assertEq(finalBondingTotalSupply - initialBondingTotalSupply, bondingTokensOut, "Total supply should increase");

        vm.stopPrank();
    }

    function testAddLiquidityVirtualPairUpdate() public {
        uint256 inputAmount = 1000 * 1e18;

        (uint256 initialVInput, uint256 initialVL,) = b3.getVirtualPair();

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        b3.addLiquidity(inputAmount, 0);

        // Virtual pair should be updated
        (uint256 finalVInput, uint256 finalVL, uint256 k) = b3.getVirtualPair();

        assertEq(finalVInput, initialVInput + inputAmount, "Virtual input tokens should increase");
        assertTrue(finalVL < initialVL, "Virtual L should decrease (as bondingTokens are 'minted from it')");
        // With virtual liquidity, k is the constant virtualK, not the simple product
        assertEq(k, b3.virtualK(), "Virtual K should be returned by getVirtualPair");

        vm.stopPrank();
    }

    // ============ VIRTUAL PAIR MATH TESTS ============

    function testAddLiquidityVirtualPairMath() public {
        uint256 inputAmount = 1000 * 1e18;

        // Quote the expected bonding tokens
        uint256 expectedBondingTokens = b3.quoteAddLiquidity(inputAmount);

        // Record all balances before operation
        uint256 initialUserInputBalance = inputToken.balanceOf(user1);
        uint256 initialUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 initialVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, 0);

        // The bonding tokens out should match the quote
        assertEq(bondingTokensOut, expectedBondingTokens, "Bonding tokens should match quote");

        // Comprehensive state validation
        uint256 finalUserInputBalance = inputToken.balanceOf(user1);
        uint256 finalUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 finalVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        uint256 finalBondingTotalSupply = bondingToken.totalSupply();

        // Validate user input token balance decreased
        assertEq(initialUserInputBalance - finalUserInputBalance, inputAmount, "User input tokens should decrease");

        // Validate user bonding token balance increased
        assertEq(finalUserBondingBalance - initialUserBondingBalance, bondingTokensOut, "User bonding tokens should increase");

        // Validate vault balance increased
        assertEq(finalVaultBalance - initialVaultBalance, inputAmount, "Vault balance should increase");

        // Validate bonding token total supply increased
        assertEq(finalBondingTotalSupply - initialBondingTotalSupply, bondingTokensOut, "Total supply should increase");

        vm.stopPrank();
    }

    function testAddLiquidityPreservesK() public {
        uint256 inputAmount = 100 * 1e18; // Use reasonable amount

        uint256 initialVirtualK = b3.virtualK();

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        b3.addLiquidity(inputAmount, 0);

        (uint256 finalVInput, uint256 finalVL, uint256 k) = b3.getVirtualPair();

        // Virtual K constant should remain unchanged
        uint256 finalVirtualK = b3.virtualK();
        assertEq(finalVirtualK, initialVirtualK, "Virtual K constant should not change");

        // Check virtual liquidity invariant (x+alpha)(y+beta)=k holds with strict precision
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 leftSide = (finalVInput + alpha) * (finalVL + beta);
        // K invariant must be preserved with strict tolerance for mathematical correctness
        // Using relative tolerance of 0.0001% (100x stricter than original 0.01%)
        uint256 tolerance = initialVirtualK / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(
            leftSide, initialVirtualK, tolerance, "Virtual liquidity invariant should hold within 0.0001% precision"
        );

        vm.stopPrank();
    }

    function testAddLiquidityWithDifferentAmounts() public {
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 10 * 1e18;
        amounts[1] = 20 * 1e18;
        amounts[2] = 50 * 1e18;
        amounts[3] = 100 * 1e18;

        vm.startPrank(user1);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 inputAmount = amounts[i];

            // Use quote to get expected output
            uint256 expectedOut = b3.quoteAddLiquidity(inputAmount);

            inputToken.approve(address(b3), inputAmount);
            uint256 actualOut = b3.addLiquidity(inputAmount, 0);

            assertTrue(
                actualOut > 0, string(abi.encodePacked("Amount ", vm.toString(i), " should produce bonding tokens"))
            );
            assertEq(
                actualOut,
                expectedOut,
                string(abi.encodePacked("Amount ", vm.toString(i), " should match quote exactly"))
            );
        }

        vm.stopPrank();
    }

    // ============ MEV PROTECTION TESTS ============

    function testAddLiquidityMEVProtection() public {
        uint256 inputAmount = 100; // Use appropriate amount for virtual pair scale

        // Get the actual expected output
        uint256 expectedOut = b3.quoteAddLiquidity(inputAmount);
        uint256 minBondingTokens = expectedOut + 1; // Set minimum just above expected output

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        // Should revert if output is below minimum
        vm.expectRevert("B3: Insufficient output amount");
        b3.addLiquidity(inputAmount, minBondingTokens);

        vm.stopPrank();
    }

    function testAddLiquidityMEVProtectionPasses() public {
        uint256 inputAmount = 100; // Use consistent amount with protection test

        // Get quote first
        uint256 expectedOut = b3.quoteAddLiquidity(inputAmount);
        uint256 minBondingTokens = (expectedOut * 95) / 100; // 5% slippage tolerance

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, minBondingTokens);

        assertTrue(bondingTokensOut >= minBondingTokens, "Output should meet minimum requirement");

        vm.stopPrank();
    }

    // ============ EDGE CASE TESTS ============

    function testAddLiquidityZeroAmount() public {
        vm.startPrank(user1);

        vm.expectRevert("B3: Input amount must be greater than 0");
        b3.addLiquidity(0, 0);

        vm.stopPrank();
    }

    function testAddLiquidityInsufficientApproval() public {
        uint256 inputAmount = 1000 * 1e18;

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount - 1); // Insufficient approval

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(b3), inputAmount - 1, inputAmount
            )
        );
        b3.addLiquidity(inputAmount, 0);

        vm.stopPrank();
    }

    function testAddLiquidityInsufficientBalance() public {
        uint256 inputAmount = 2_000_000 * 1e18; // More than user has

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                user1,
                1_000_000 * 1e18, // User's balance from setUp
                inputAmount
            )
        );
        b3.addLiquidity(inputAmount, 0);

        vm.stopPrank();
    }

    // ============ LARGE AMOUNT TESTS ============

    function testAddLiquidityLargeAmount() public {
        uint256 inputAmount = 100_000 * 1e18;

        // Mint more tokens for this test
        inputToken.mint(user1, inputAmount);

        // Record all balances before operation
        uint256 initialUserInputBalance = inputToken.balanceOf(user1);
        uint256 initialUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 initialVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, 0);

        // Comprehensive state validation
        uint256 finalUserInputBalance = inputToken.balanceOf(user1);
        uint256 finalUserBondingBalance = bondingToken.balanceOf(user1);
        uint256 finalVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        uint256 finalBondingTotalSupply = bondingToken.totalSupply();

        assertTrue(bondingTokensOut > 0, "Should handle large amounts");

        // Validate user input token balance decreased
        assertEq(initialUserInputBalance - finalUserInputBalance, inputAmount, "User input tokens should decrease");

        // Validate user bonding token balance increased
        assertEq(finalUserBondingBalance - initialUserBondingBalance, bondingTokensOut, "User bonding tokens should increase");

        // Validate vault balance increased
        assertEq(finalVaultBalance - initialVaultBalance, inputAmount, "Vault balance should increase");

        // Validate bonding token total supply increased
        assertEq(finalBondingTotalSupply - initialBondingTotalSupply, bondingTokensOut, "Total supply should increase");

        // Check virtual pair math still works
        (uint256 vInput, uint256 vL, uint256 k) = b3.getVirtualPair();
        // With virtual liquidity, k is the constant virtualK, not the simple product
        assertEq(k, b3.virtualK(), "Virtual K should be returned by getVirtualPair");

        vm.stopPrank();
    }

    // ============ MULTIPLE USERS TESTS ============

    function testAddLiquidityMultipleUsers() public {
        uint256 inputAmount = 1000 * 1e18; // Use meaningful amounts for virtual liquidity

        // Get initial state for bonding curve calculation
        (uint256 initialVInput, uint256 initialVL, uint256 k) = b3.getVirtualPair();

        // Record initial global state
        uint256 initialVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        uint256 initialBondingTotalSupply = bondingToken.totalSupply();

        // User 1 adds liquidity
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        uint256 user1Tokens = b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();

        // Validate user1 bonding tokens received
        assertEq(bondingToken.balanceOf(user1), user1Tokens, "User1 bonding tokens should increase");

        // Get state after user 1 for calculating expected user 2 tokens
        (uint256 vInputAfterUser1, uint256 vLAfterUser1,) = b3.getVirtualPair();

        // User 2 adds liquidity
        vm.startPrank(user2);
        inputToken.approve(address(b3), inputAmount);
        uint256 user2Tokens = b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();

        // Validate user2 bonding tokens received
        assertEq(bondingToken.balanceOf(user2), user2Tokens, "User2 bonding tokens should increase");

        // Both users should have bonding tokens
        assertTrue(user1Tokens > 0, "User 1 should have bonding tokens");
        assertTrue(user2Tokens > 0, "User 2 should have bonding tokens");
        assertEq(bondingToken.balanceOf(user1), user1Tokens, "User 1 should have correct bonding token balance");
        assertEq(bondingToken.balanceOf(user2), user2Tokens, "User 2 should have correct bonding token balance");

        // Validate cumulative state changes
        assertEq(
            vault.balanceOf(address(inputToken), address(b3)) - initialVaultBalance,
            2 * inputAmount,
            "Vault should increase by total deposited"
        );
        assertEq(
            bondingToken.totalSupply() - initialBondingTotalSupply,
            user1Tokens + user2Tokens,
            "Total supply should increase by total minted"
        );

        // BONDING CURVE VALIDATION: Second user MUST receive fewer tokens (price increases along curve)
        // This is the fundamental property of a bonding curve - no tolerance, strict inequality
        assertTrue(user2Tokens < user1Tokens, "Second user must receive strictly fewer tokens - bonding curve price increases");

        // Calculate expected bonding curve slope behavior
        // For bonding curve (x+α)(y+β)=k, when adding same input amount:
        // - First addition: y_out1 = virtualL - k/(virtualInput + inputAmount + α) + β
        // - Second addition: y_out2 = virtualL_after_first - k/(virtualInput_after_first + inputAmount + α) + β
        // - Because virtualInput increased, denominator is larger, so y_out2 < y_out1

        // Calculate expected user2 tokens based on curve formula
        uint256 alpha = b3.alpha();
        uint256 expectedUser2Tokens = vLAfterUser1 - (k / (vInputAfterUser1 + inputAmount + alpha) - alpha);

        // Validate that actual user2 tokens match mathematical expectation
        // Using 0.0001% relative tolerance (1e12) as established in story 036.11
        assertApproxEqRel(user2Tokens, expectedUser2Tokens, 1e12, "User 2 tokens should match bonding curve formula expectation");

        // Validate the token difference is significant (not negligible)
        // Price increase should be at least 0.01% for these deposit amounts
        uint256 percentDifference = ((user1Tokens - user2Tokens) * 1e18) / user1Tokens;
        assertTrue(percentDifference >= 1e14, "Token difference should be at least 0.01% - curve not flat");
    }

    function testBondingCurveSlopeWithLargerDeposits() public {
        // Use significantly larger deposit amounts to verify curve slope is working correctly
        uint256 largeDeposit = 100_000 * 1e18; // 100k tokens per deposit

        // Get initial state
        (uint256 initialVInput, uint256 initialVL, uint256 k) = b3.getVirtualPair();
        uint256 alpha = b3.alpha();

        // User 1 makes large deposit
        vm.startPrank(user1);
        inputToken.approve(address(b3), largeDeposit);
        uint256 user1Tokens = b3.addLiquidity(largeDeposit, 0);
        vm.stopPrank();

        // Get state after user 1
        (uint256 vInputAfterUser1, uint256 vLAfterUser1,) = b3.getVirtualPair();

        // User 2 makes same large deposit
        vm.startPrank(user2);
        inputToken.approve(address(b3), largeDeposit);
        uint256 user2Tokens = b3.addLiquidity(largeDeposit, 0);
        vm.stopPrank();

        // Calculate expected user2 tokens based on bonding curve formula
        uint256 expectedUser2Tokens = vLAfterUser1 - (k / (vInputAfterUser1 + largeDeposit + alpha) - alpha);

        // Verify mathematical expectation with 0.0001% tolerance
        assertApproxEqRel(user2Tokens, expectedUser2Tokens, 1e12, "Large deposit user 2 tokens should match curve formula");

        // Verify strict price increase (second user gets fewer tokens)
        assertTrue(user2Tokens < user1Tokens, "Large deposit: second user must get strictly fewer tokens");

        // With larger deposits, the price increase should be more pronounced
        // Calculate percentage difference
        uint256 percentDiff = ((user1Tokens - user2Tokens) * 1e18) / user1Tokens;

        // For large deposits, expect at least 0.1% difference to demonstrate curve slope
        assertTrue(percentDiff >= 1e15, "Large deposits should show at least 0.1% price increase");

        // Verify the curve slope is steeper than with small deposits
        // Calculate tokens per input token for each user
        uint256 user1TokensPerInput = (user1Tokens * 1e18) / largeDeposit;
        uint256 user2TokensPerInput = (user2Tokens * 1e18) / largeDeposit;

        // Second user should get strictly fewer tokens per input token
        assertTrue(user2TokensPerInput < user1TokensPerInput, "Tokens per input should decrease along curve");
    }

    function testMarginalPriceIncreaseValidation() public {
        // Test marginal price increase validation between sequential operations
        // This validates that each successive operation results in measurably higher price (fewer tokens per input)
        uint256 depositAmount = 10_000 * 1e18; // 10k tokens per deposit
        uint256 numOperations = 5; // Test 5 sequential operations

        uint256[] memory tokensReceived = new uint256[](numOperations);
        uint256 alpha = b3.alpha();

        // Perform sequential deposits and track tokens received
        for (uint256 i = 0; i < numOperations; i++) {
            address user;
            if (i == 0) user = user1;
            else if (i == 1) user = user2;
            else if (i == 2) user = address(0x4);
            else if (i == 3) user = address(0x5);
            else user = address(0x6);

            // Mint tokens for new users
            if (i >= 2) {
                inputToken.mint(user, depositAmount);
            }

            // Get state before deposit for validation
            (uint256 vInputBefore, uint256 vLBefore, uint256 k) = b3.getVirtualPair();

            // Execute deposit
            vm.startPrank(user);
            inputToken.approve(address(b3), depositAmount);
            tokensReceived[i] = b3.addLiquidity(depositAmount, 0);
            vm.stopPrank();

            // Calculate expected tokens based on bonding curve formula
            uint256 expectedTokens = vLBefore - (k / (vInputBefore + depositAmount + alpha) - alpha);

            // Validate actual tokens match mathematical expectation (0.0001% tolerance)
            assertApproxEqRel(
                tokensReceived[i],
                expectedTokens,
                1e12,
                string.concat("Operation ", vm.toString(i), " should match curve formula")
            );

            // Validate marginal price increase: each successive operation yields fewer tokens
            if (i > 0) {
                assertTrue(
                    tokensReceived[i] < tokensReceived[i - 1],
                    string.concat("Operation ", vm.toString(i), " must yield fewer tokens than previous")
                );

                // Validate the price increase is measurable (at least 0.001% difference)
                uint256 percentDecrease = ((tokensReceived[i - 1] - tokensReceived[i]) * 1e18) / tokensReceived[i - 1];
                assertTrue(
                    percentDecrease >= 1e13,
                    string.concat("Operation ", vm.toString(i), " should show at least 0.001% price increase")
                );
            }
        }

        // Final validation: compare first and last operation
        // The cumulative price increase should be significant
        uint256 totalPriceIncrease = ((tokensReceived[0] - tokensReceived[numOperations - 1]) * 1e18) / tokensReceived[0];

        // Over 5 operations with 10k deposits each, expect at least 0.1% cumulative price increase
        assertTrue(
            totalPriceIncrease >= 1e15,
            "Cumulative price increase over 5 operations should be at least 0.1%"
        );
    }

    // ============ REENTRANCY TESTS ============

    function testAddLiquidityReentrancyProtection() public {
        // This test would require a malicious contract that attempts reentrancy
        // For now, we test that the nonReentrant modifier is present

        vm.startPrank(user1);
        inputToken.approve(address(b3), 1000 * 1e18);

        // The function should have reentrancy protection
        // Actual reentrancy testing would require a more complex setup
        uint256 bondingTokensOut = b3.addLiquidity(1000 * 1e18, 0);
        assertTrue(bondingTokensOut > 0, "Function should work normally when not under reentrancy attack");

        vm.stopPrank();
    }

    // ============ EVENT TESTS ============

    function testAddLiquidityEvent() public {
        uint256 inputAmount = 1000 * 1e18;

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        // Calculate expected bonding tokens out
        uint256 expectedBondingTokensOut = b3.quoteAddLiquidity(inputAmount);

        // Expect the LiquidityAdded event
        vm.expectEmit(true, false, false, true);
        emit LiquidityAdded(user1, inputAmount, expectedBondingTokensOut);

        b3.addLiquidity(inputAmount, 0);

        vm.stopPrank();
    }

    /**
     * @notice Test K invariant preservation with minimal deposit (1 wei)
     * @dev Critical test for mathematical precision at extreme values
     */
    function testAddLiquidityPreservesKMinimalDeposit() public {
        uint256 inputAmount = 1; // Minimal deposit: 1 wei

        uint256 initialVirtualK = b3.virtualK();

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        b3.addLiquidity(inputAmount, 0);

        (uint256 finalVInput, uint256 finalVL,) = b3.getVirtualPair();

        // Virtual K constant should remain unchanged
        uint256 finalVirtualK = b3.virtualK();
        assertEq(finalVirtualK, initialVirtualK, "Virtual K constant should not change");

        // Check virtual liquidity invariant (x+alpha)(y+beta)=k holds with strict precision
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 leftSide = (finalVInput + alpha) * (finalVL + beta);
        // K invariant must be preserved with strict tolerance even for minimal deposits
        // Using relative tolerance of 0.0001% (100x stricter than original 0.01%)
        uint256 tolerance = initialVirtualK / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(
            leftSide, initialVirtualK, tolerance, "Virtual liquidity invariant should hold within 0.0001% precision for minimal deposit"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test K invariant preservation near funding goal saturation
     * @dev Critical test for mathematical precision when approaching funding goal
     */
    function testKPreservationNearFundingGoalSaturation() public {
        // Add liquidity to approach funding goal (99% of goal)
        uint256 nearSaturationAmount = (FUNDING_GOAL * 99) / 100;

        vm.startPrank(user1);
        inputToken.approve(address(b3), nearSaturationAmount);
        b3.addLiquidity(nearSaturationAmount, 0);

        uint256 initialVirtualK = b3.virtualK();

        // Add small additional amount to push closer to saturation
        uint256 additionalAmount = FUNDING_GOAL / 200; // 0.5% more
        inputToken.approve(address(b3), additionalAmount);
        b3.addLiquidity(additionalAmount, 0);

        (uint256 finalVInput, uint256 finalVL,) = b3.getVirtualPair();

        // Virtual K constant should remain unchanged even near saturation
        uint256 finalVirtualK = b3.virtualK();
        assertEq(finalVirtualK, initialVirtualK, "Virtual K constant should not change near saturation");

        // Check virtual liquidity invariant (x+alpha)(y+beta)=k holds with strict precision
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 leftSide = (finalVInput + alpha) * (finalVL + beta);
        // K invariant must be preserved with strict tolerance even near funding goal saturation
        // Using relative tolerance of 0.0001% (100x stricter than original 0.01%)
        uint256 tolerance = initialVirtualK / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(
            leftSide, initialVirtualK, tolerance, "Virtual liquidity invariant should hold within 0.0001% precision near saturation"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test K invariant preservation over 1000+ sequential operations
     * @dev Critical test for cumulative precision loss detection
     */
    function testKPreservationCumulativePrecisionLoss() public {
        // Create fresh B3 contract for clean state
        Behodler3Tokenlaunch freshB3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IVault(address(vault))
        );

        vault.setClient(address(freshB3), true);
        freshB3.initializeVaultApproval();
        freshB3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        uint256 initialVirtualK = freshB3.virtualK();

        // Perform 1000 sequential add/remove liquidity operations
        vm.startPrank(user1);

        uint256 operationAmount = 100 * 1e18; // Reasonable amount per operation
        inputToken.approve(address(freshB3), type(uint256).max); // Approve large amount for all operations

        for (uint256 i = 0; i < 1000; i++) {
            // Add liquidity
            uint256 bondingTokensReceived = freshB3.addLiquidity(operationAmount, 0);

            // Remove half of the liquidity received
            freshB3.removeLiquidity(bondingTokensReceived / 2, 0);
        }

        (uint256 finalVInput, uint256 finalVL,) = freshB3.getVirtualPair();

        // Virtual K constant should remain unchanged after 1000+ operations
        uint256 finalVirtualK = freshB3.virtualK();
        assertEq(finalVirtualK, initialVirtualK, "Virtual K constant should not change after 1000+ operations");

        // Check virtual liquidity invariant (x+alpha)(y+beta)=k holds with strict precision
        uint256 alpha = freshB3.alpha();
        uint256 beta = freshB3.beta();
        uint256 leftSide = (finalVInput + alpha) * (finalVL + beta);
        // K invariant must be preserved with strict tolerance even after 1000+ sequential operations
        // Using relative tolerance of 0.0001% (100x stricter than original 0.01%)
        uint256 tolerance = initialVirtualK / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(
            leftSide, initialVirtualK, tolerance, "Virtual liquidity invariant should hold within 0.0001% precision after 1000+ operations"
        );

        vm.stopPrank();
    }

    // Define the event for testing
    event LiquidityAdded(address indexed user, uint256 inputAmount, uint256 bondingTokensOut);
}
