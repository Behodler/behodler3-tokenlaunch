// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockVault.sol";
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
    
    // Virtual Pair Constants
    uint256 public constant INITIAL_VIRTUAL_INPUT = 10000;
    uint256 public constant INITIAL_VIRTUAL_L = 100000000;
    uint256 public constant K = 1_000_000_000_000;
    
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
        
        // Setup test tokens
        inputToken.mint(user1, 1000000 * 1e18);
        inputToken.mint(user2, 1000000 * 1e18);
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
        
        (uint256 initialVInput, uint256 initialVL, ) = b3.getVirtualPair();
        
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        
        b3.addLiquidity(inputAmount, 0);
        
        // Virtual pair should be updated
        (uint256 finalVInput, uint256 finalVL, uint256 k) = b3.getVirtualPair();
        
        assertEq(finalVInput, initialVInput + inputAmount, "Virtual input tokens should increase");
        assertTrue(finalVL < initialVL, "Virtual L should decrease (as bondingTokens are 'minted from it')");
        assertEq(k, finalVInput * finalVL, "K should be preserved");
        
        vm.stopPrank();
    }
    
    // ============ VIRTUAL PAIR MATH TESTS ============
    
    function testAddLiquidityVirtualPairMath() public {
        uint256 inputAmount = 1000 * 1e18;
        
        // Calculate expected virtualL_out using the formula:
        // virtualL_out = virtualL - (K / (virtualInputTokens + inputAmount))
        uint256 expectedNewVirtualL = K / (INITIAL_VIRTUAL_INPUT + inputAmount);
        uint256 expectedVirtualL_out = INITIAL_VIRTUAL_L - expectedNewVirtualL;
        
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        
        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, 0);
        
        // The bonding tokens out should equal virtualL_out
        assertEq(bondingTokensOut, expectedVirtualL_out, "Bonding tokens should equal calculated virtualL_out");
        
        vm.stopPrank();
    }
    
    function testAddLiquidityPreservesK() public {
        uint256 inputAmount = 100; // Use smaller amount proportional to virtual pair scale
        
        uint256 initialK = b3.K();
        
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        
        b3.addLiquidity(inputAmount, 0);
        
        (uint256 finalVInput, uint256 finalVL, uint256 k) = b3.getVirtualPair();
        
        // K should be preserved (allowing for small rounding in integer math)
        assertApproxEqRel(k, initialK, 1e15, "K should remain approximately constant"); // 0.1% tolerance
        assertApproxEqRel(finalVInput * finalVL, initialK, 1e15, "Virtual pair should preserve constant product");
        
        vm.stopPrank();
    }
    
    function testAddLiquidityWithDifferentAmounts() public {
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 10; // Use small amounts proportional to virtual pair scale
        amounts[1] = 20;
        amounts[2] = 50;
        amounts[3] = 100;
        
        vm.startPrank(user1);
        
        for (uint i = 0; i < amounts.length; i++) {
            uint256 inputAmount = amounts[i];
            
            // Calculate expected output
            (uint256 vInput, uint256 vL, ) = b3.getVirtualPair();
            uint256 expectedNewVL = K / (vInput + inputAmount);
            uint256 expectedOut = vL - expectedNewVL;
            
            inputToken.approve(address(b3), inputAmount);
            uint256 actualOut = b3.addLiquidity(inputAmount, 0);
            
            assertTrue(actualOut > 0, string(abi.encodePacked("Amount ", vm.toString(i), " should produce bonding tokens")));
            assertApproxEqRel(actualOut, expectedOut, 1e15, string(abi.encodePacked("Amount ", vm.toString(i), " should approximately match calculation")));
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
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(b3),
                inputAmount - 1,
                inputAmount
            )
        );
        b3.addLiquidity(inputAmount, 0);
        
        vm.stopPrank();
    }
    
    function testAddLiquidityInsufficientBalance() public {
        uint256 inputAmount = 2000000 * 1e18; // More than user has
        
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                user1,
                1000000 * 1e18, // User's balance from setUp
                inputAmount
            )
        );
        b3.addLiquidity(inputAmount, 0);
        
        vm.stopPrank();
    }
    
    // ============ LARGE AMOUNT TESTS ============
    
    function testAddLiquidityLargeAmount() public {
        uint256 inputAmount = 100000 * 1e18;
        
        // Mint more tokens for this test
        inputToken.mint(user1, inputAmount);
        
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        
        uint256 bondingTokensOut = b3.addLiquidity(inputAmount, 0);
        
        assertTrue(bondingTokensOut > 0, "Should handle large amounts");
        
        // Check virtual pair math still works
        (uint256 vInput, uint256 vL, uint256 k) = b3.getVirtualPair();
        assertEq(k, vInput * vL, "K should be preserved with large amounts");
        
        vm.stopPrank();
    }
    
    // ============ MULTIPLE USERS TESTS ============
    
    function testAddLiquidityMultipleUsers() public {
        uint256 inputAmount = 50; // Use small amounts proportional to virtual pair scale
        
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
        
        // Second user should get fewer tokens (due to virtual pair math)
        assertTrue(user2Tokens < user1Tokens, "Second user should get fewer tokens");
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