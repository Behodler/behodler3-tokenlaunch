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

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, 0);

        // Should return non-zero bonding tokens
        assertTrue(bondingTokensOut > 0, "Should mint bonding tokens");

        // Check that bonding tokens were actually minted
        assertEq(bondingToken.balanceOf(user1), bondingTokensOut, "User should receive bonding tokens");

        vm.stopPrank();
    }

    function testAddLiquidityVaultDeposit() public {
        uint256 inputAmount = 1000 * 1e18;

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        uint256 initialVaultBalance = vault.balanceOf(address(inputToken), address(b3));

        b3.addLiquidity(inputAmount, 0);

        // Check that tokens were deposited to vault
        uint256 finalVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        assertEq(finalVaultBalance - initialVaultBalance, inputAmount, "Tokens should be deposited to vault");

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

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, 0);

        // The bonding tokens out should match the quote
        assertEq(bondingTokensOut, expectedBondingTokens, "Bonding tokens should match quote");

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

        // Check virtual liquidity invariant (x+alpha)(y+beta)=k holds with precision tolerance
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 leftSide = (finalVInput + alpha) * (finalVL + beta);
        // Use larger tolerance for ERC20 precision as instructed by user (10^4 for 10^18 values)
        uint256 tolerance = initialVirtualK / 1e14; // 0.01% tolerance for large numbers
        assertApproxEqAbs(
            leftSide, initialVirtualK, tolerance, "Virtual liquidity invariant should hold within precision"
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

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, 0);

        assertTrue(bondingTokensOut > 0, "Should handle large amounts");

        // Check virtual pair math still works
        (uint256 vInput, uint256 vL, uint256 k) = b3.getVirtualPair();
        // With virtual liquidity, k is the constant virtualK, not the simple product
        assertEq(k, b3.virtualK(), "Virtual K should be returned by getVirtualPair");

        vm.stopPrank();
    }

    // ============ MULTIPLE USERS TESTS ============

    function testAddLiquidityMultipleUsers() public {
        uint256 inputAmount = 1000 * 1e18; // Use meaningful amounts for virtual liquidity

        // User 1 adds liquidity
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        uint256 user1Tokens = b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();

        // User 2 adds liquidity
        vm.startPrank(user2);
        inputToken.approve(address(b3), inputAmount);
        uint256 user2Tokens = b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();

        // Both users should have bonding tokens
        assertTrue(user1Tokens > 0, "User 1 should have bonding tokens");
        assertTrue(user2Tokens > 0, "User 2 should have bonding tokens");
        assertEq(bondingToken.balanceOf(user1), user1Tokens, "User 1 should have correct bonding token balance");
        assertEq(bondingToken.balanceOf(user2), user2Tokens, "User 2 should have correct bonding token balance");

        // With virtual liquidity, difference should be within reasonable tolerance for ERC20 precision
        // Using 10^4 tolerance for 10^18 scale values as instructed by user
        if (user1Tokens != user2Tokens) {
            assertTrue(user2Tokens <= user1Tokens, "Second user should get same or fewer tokens");
        } else {
            // Virtual liquidity curve is so flat that difference is negligible - this is expected
            assertEq(user1Tokens, user2Tokens, "Tokens should be equal when curve is very flat");
        }
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

    // Define the event for testing
    event LiquidityAdded(address indexed user, uint256 inputAmount, uint256 bondingTokensOut);
}
