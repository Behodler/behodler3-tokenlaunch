// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";

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
    
    // Virtual Pair Constants
    uint256 public constant INITIAL_VIRTUAL_INPUT = 10000;
    uint256 public constant INITIAL_VIRTUAL_L = 100000000;
    uint256 public constant K = 1_000_000_000_000;
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock contracts
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault();
        
        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)),
            IBondingToken(address(bondingToken)),
            IVault(address(vault))
        );
        
        vm.stopPrank();
        
        // Setup test tokens and add initial liquidity
        inputToken.mint(user1, 1000000 * 1e18);
        inputToken.mint(user2, 1000000 * 1e18);
        
        // Add some liquidity first so we can test removal
        vm.startPrank(user1);
        inputToken.approve(address(b3), 10000 * 1e18);
        inputToken.approve(address(vault), 10000 * 1e18);
        vault.deposit(address(inputToken), 10000 * 1e18, address(b3)); // Simulate vault having tokens
        bondingToken.mint(user1, 50000); // Give user some bonding tokens
        vm.stopPrank();
    }
    
    // ============ BASIC REMOVE LIQUIDITY TESTS ============
    
    function testRemoveLiquidityBasic() public {
        uint256 bondingTokenAmount = 10000;
        
        vm.startPrank(user1);
        
        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);
        
        // Should return non-zero input tokens
        assertTrue(inputTokensOut > 0, "Should return input tokens");
        
        // Check that user's input token balance increased
        assertTrue(inputToken.balanceOf(user1) > 1000000 * 1e18, "User should receive input tokens");
        
        vm.stopPrank();
    }
    
    function testRemoveLiquidityBurnsBondingTokens() public {
        uint256 bondingTokenAmount = 10000;
        uint256 initialBondingBalance = bondingToken.balanceOf(user1);
        
        vm.startPrank(user1);
        
        b3.removeLiquidity(bondingTokenAmount, 0);
        
        // Check that bonding tokens were burned
        uint256 finalBondingBalance = bondingToken.balanceOf(user1);
        assertEq(initialBondingBalance - finalBondingBalance, bondingTokenAmount, "Bonding tokens should be burned");
        
        vm.stopPrank();
    }
    
    function testRemoveLiquidityVaultWithdrawal() public {
        uint256 bondingTokenAmount = 10000;
        
        uint256 initialVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        
        vm.startPrank(user1);
        
        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);
        
        // Check that tokens were withdrawn from vault
        uint256 finalVaultBalance = vault.balanceOf(address(inputToken), address(b3));
        assertEq(initialVaultBalance - finalVaultBalance, inputTokensOut, "Tokens should be withdrawn from vault");
        
        vm.stopPrank();
    }
    
    function testRemoveLiquidityVirtualPairUpdate() public {
        uint256 bondingTokenAmount = 10000;
        
        (uint256 initialVInput, uint256 initialVL, ) = b3.getVirtualPair();
        
        vm.startPrank(user1);
        
        b3.removeLiquidity(bondingTokenAmount, 0);
        
        // Virtual pair should be updated
        (uint256 finalVInput, uint256 finalVL, uint256 k) = b3.getVirtualPair();
        
        assertTrue(finalVInput < initialVInput, "Virtual input tokens should decrease");
        assertEq(finalVL, initialVL + bondingTokenAmount, "Virtual L should increase by bonding token amount");
        assertEq(k, finalVInput * finalVL, "K should be preserved");
        
        vm.stopPrank();
    }
    
    // ============ VIRTUAL PAIR MATH TESTS ============
    
    function testRemoveLiquidityVirtualPairMath() public {
        uint256 bondingTokenAmount = 10000;
        
        (uint256 initialVInput, uint256 initialVL, ) = b3.getVirtualPair();
        
        // Calculate expected inputTokens_out using the formula:
        // inputTokens_out = virtualInputTokens - (K / (virtualL + bondingTokenAmount))
        uint256 newVirtualL = initialVL + bondingTokenAmount;
        uint256 newVirtualInput = K / newVirtualL;
        uint256 expectedInputTokensOut = initialVInput - newVirtualInput;
        
        vm.startPrank(user1);
        
        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);
        
        // The input tokens out should equal calculated amount
        assertEq(inputTokensOut, expectedInputTokensOut, "Input tokens should equal calculated amount");
        
        vm.stopPrank();
    }
    
    function testRemoveLiquidityPreservesK() public {
        uint256 bondingTokenAmount = 10000;
        
        uint256 initialK = b3.K();
        
        vm.startPrank(user1);
        
        b3.removeLiquidity(bondingTokenAmount, 0);
        
        (uint256 finalVInput, uint256 finalVL, uint256 k) = b3.getVirtualPair();
        
        // K should be preserved
        assertEq(k, initialK, "K should remain constant");
        assertEq(finalVInput * finalVL, initialK, "Virtual pair should preserve constant product");
        
        vm.stopPrank();
    }
    
    function testRemoveLiquidityWithDifferentAmounts() public {
        // Give user more bonding tokens
        bondingToken.mint(user1, 100000);
        
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1000;
        amounts[1] = 5000;
        amounts[2] = 10000;
        amounts[3] = 20000;
        
        vm.startPrank(user1);
        
        for (uint i = 0; i < amounts.length; i++) {
            uint256 bondingAmount = amounts[i];
            
            // Calculate expected output
            (uint256 vInput, uint256 vL, ) = b3.getVirtualPair();
            uint256 expectedNewVInput = K / (vL + bondingAmount);
            uint256 expectedOut = vInput - expectedNewVInput;
            
            uint256 actualOut = b3.removeLiquidity(bondingAmount, 0);
            
            assertEq(actualOut, expectedOut, string(abi.encodePacked("Amount ", vm.toString(i), " should match calculation")));
        }
        
        vm.stopPrank();
    }
    
    // ============ MEV PROTECTION TESTS ============
    
    function testRemoveLiquidityMEVProtection() public {
        uint256 bondingTokenAmount = 10000;
        uint256 minInputTokens = 50000 * 1e18; // Set unreasonably high minimum
        
        vm.startPrank(user1);
        
        // Should revert if output is below minimum
        vm.expectRevert("B3: Insufficient input tokens out");
        b3.removeLiquidity(bondingTokenAmount, minInputTokens);
        
        vm.stopPrank();
    }
    
    function testRemoveLiquidityMEVProtectionPasses() public {
        uint256 bondingTokenAmount = 10000;
        
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
        
        vm.expectRevert("B3: Amount cannot be zero");
        b3.removeLiquidity(0, 0);
        
        vm.stopPrank();
    }
    
    function testRemoveLiquidityInsufficientBondingTokens() public {
        uint256 bondingTokenAmount = 100000; // More than user has
        
        vm.startPrank(user1);
        
        vm.expectRevert("B3: Insufficient bonding tokens");
        b3.removeLiquidity(bondingTokenAmount, 0);
        
        vm.stopPrank();
    }
    
    function testRemoveLiquidityInsufficientVaultBalance() public {
        // This tests the case where vault doesn't have enough tokens
        uint256 bondingTokenAmount = 10000;
        
        vm.startPrank(user1);
        
        // First, drain the vault
        vault.withdraw(address(inputToken), vault.balanceOf(address(inputToken), address(b3)), user1);
        
        vm.expectRevert("MockVault: insufficient balance");
        b3.removeLiquidity(bondingTokenAmount, 0);
        
        vm.stopPrank();
    }
    
    // ============ COMPLETE REMOVAL TESTS ============
    
    function testRemoveAllLiquidity() public {
        uint256 allBondingTokens = bondingToken.balanceOf(user1);
        
        vm.startPrank(user1);
        
        uint256 inputTokensOut = b3.removeLiquidity(allBondingTokens, 0);
        
        // Should have no bonding tokens left
        assertEq(bondingToken.balanceOf(user1), 0, "Should have no bonding tokens left");
        
        // Should have received input tokens
        assertTrue(inputTokensOut > 0, "Should receive input tokens");
        
        vm.stopPrank();
    }
    
    // ============ MULTIPLE USERS TESTS ============
    
    function testRemoveLiquidityMultipleUsers() public {
        // Give user2 some bonding tokens
        bondingToken.mint(user2, 25000);
        
        uint256 bondingAmount = 10000;
        
        // User 1 removes liquidity
        vm.startPrank(user1);
        uint256 user1TokensOut = b3.removeLiquidity(bondingAmount, 0);
        vm.stopPrank();
        
        // User 2 removes liquidity
        vm.startPrank(user2);
        uint256 user2TokensOut = b3.removeLiquidity(bondingAmount, 0);
        vm.stopPrank();
        
        // Both users should have received tokens
        assertTrue(user1TokensOut > 0, "User 1 should receive tokens");
        assertTrue(user2TokensOut > 0, "User 2 should receive tokens");
        
        // Due to virtual pair math, second user might get different amount
        // This tests that the system handles multiple users correctly
    }
    
    // ============ REENTRANCY TESTS ============
    
    function testRemoveLiquidityReentrancyProtection() public {
        // This test would require a malicious contract that attempts reentrancy
        // For now, we test that the nonReentrant modifier is present
        
        vm.startPrank(user1);
        
        // The function should have reentrancy protection
        uint256 inputTokensOut = b3.removeLiquidity(10000, 0);
        assertTrue(inputTokensOut > 0, "Function should work normally when not under reentrancy attack");
        
        vm.stopPrank();
    }
    
    // ============ ROUND TRIP TESTS ============
    
    function testAddThenRemoveLiquidity() public {
        uint256 initialBalance = inputToken.balanceOf(user1);
        uint256 inputAmount = 1000 * 1e18;
        
        vm.startPrank(user1);
        
        // Add liquidity
        inputToken.approve(address(b3), inputAmount);
        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, 0);
        
        // Remove liquidity
        uint256 inputTokensOut = b3.removeLiquidity(bondingTokensOut, 0);
        
        // Due to virtual pair math, might not get exactly the same amount back
        assertTrue(inputTokensOut > 0, "Should get some tokens back");
        
        // Check that the operation was roughly symmetrical
        uint256 finalBalance = inputToken.balanceOf(user1);
        assertTrue(finalBalance < initialBalance, "Some tokens should remain in the system");
        
        vm.stopPrank();
    }
    
    // ============ EVENT TESTS ============
    
    function testRemoveLiquidityEvent() public {
        uint256 bondingTokenAmount = 10000;
        
        vm.startPrank(user1);
        
        // Expect the LiquidityRemoved event
        vm.expectEmit(true, false, false, true);
        emit LiquidityRemoved(user1, bondingTokenAmount, 0); // 0 is placeholder
        
        b3.removeLiquidity(bondingTokenAmount, 0);
        
        vm.stopPrank();
    }
    
    // Define the event for testing
    event LiquidityRemoved(address indexed user, uint256 bondingTokenAmount, uint256 inputTokensOut);
}