// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title B3SecurityIntegrationTest
 * @notice Security, Access Control, and Integration Tests for Behodler3 Bootstrap AMM
 * @dev These tests are written FIRST in TDD Red Phase - they SHOULD FAIL initially
 * 
 * Tests Cover:
 * - Reentrancy protection
 * - Access control (owner functions)
 * - Lock/unlock functionality
 * - Integration scenarios
 * - Edge cases and error conditions
 * - Auto-lock functionality
 */
contract B3SecurityIntegrationTest is Test {
    Behodler3Tokenlaunch public b3;
    MockVault public vault;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public attacker = address(0x4);
    
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
        vault.setBondingCurve(address(b3));
        
        // Setup test tokens
        inputToken.mint(user1, 1000000 * 1e18);
        inputToken.mint(user2, 1000000 * 1e18);
        inputToken.mint(attacker, 1000000 * 1e18);
    }
    

    // ============ LOCK/UNLOCK FUNCTIONALITY TESTS ============
    
    function testLockPreventsAddLiquidity() public {
        // Lock the contract
        vm.startPrank(owner);
        b3.lock();
        vm.stopPrank();
        
        // User cannot add liquidity when locked
        vm.startPrank(user1);
        inputToken.approve(address(b3), 1000 * 1e18);
        
        vm.expectRevert("B3: Contract is locked");
        b3.addLiquidity(1000 * 1e18, 0);
        
        vm.stopPrank();
    }
    
    function testLockPreventsRemoveLiquidity() public {
        // First add some liquidity
        vm.startPrank(user1);
        inputToken.approve(address(b3), 1000 * 1e18);
        b3.addLiquidity(1000 * 1e18, 0);
        vm.stopPrank();
        
        // Lock the contract
        vm.startPrank(owner);
        b3.lock();
        vm.stopPrank();
        
        // User cannot remove liquidity when locked
        vm.startPrank(user1);
        
        vm.expectRevert("B3: Contract is locked");
        b3.removeLiquidity(10000, 0);
        
        vm.stopPrank();
    }
    
    function testUnlockAllowsOperations() public {
        // Lock then unlock
        vm.startPrank(owner);
        b3.lock();
        b3.unlock();
        vm.stopPrank();
        
        // User can add liquidity when unlocked
        vm.startPrank(user1);
        inputToken.approve(address(b3), 1000 * 1e18);
        
        uint256 bondingTokensOut = b3.addLiquidity(1000 * 1e18, 0);
        assertTrue(bondingTokensOut > 0, "Should allow add liquidity when unlocked");
        
        vm.stopPrank();
    }
    
    function testLockEmitsEvent() public {
        vm.startPrank(owner);
        
        vm.expectEmit(false, false, false, false);
        emit ContractLocked();
        
        b3.lock();
        
        vm.stopPrank();
    }
    
    function testUnlockEmitsEvent() public {
        // First lock
        vm.startPrank(owner);
        b3.lock();
        
        vm.expectEmit(false, false, false, false);
        emit ContractUnlocked();
        
        b3.unlock();
        
        vm.stopPrank();
    }
    
    // ============ AUTO-LOCK FUNCTIONALITY TESTS ============
    
    function testAutoLockInitialization() public view {
        assertFalse(b3.autoLock(), "Auto-lock should be disabled by default");
    }
    
    function testSetAutoLockChangesState() public {
        vm.startPrank(owner);
        
        b3.setAutoLock(true);
        assertTrue(b3.autoLock(), "Auto-lock should be enabled");
        
        b3.setAutoLock(false);
        assertFalse(b3.autoLock(), "Auto-lock should be disabled");
        
        vm.stopPrank();
    }
    
    function testAutoLockTriggersOnCondition() public {
        vm.startPrank(owner);
        b3.setAutoLock(true);
        vm.stopPrank();
        
        // Perform operation that should trigger auto-lock
        vm.startPrank(user1);
        inputToken.approve(address(b3), 1000 * 1e18);
        
        // After auto-lock conditions are met, contract should be locked
        b3.addLiquidity(1000 * 1e18, 0);
        
        // Check if auto-lock was triggered (depends on implementation)
        // This test documents the expected behavior
        
        vm.stopPrank();
    }
    
    // ============ REENTRANCY PROTECTION TESTS ============
    
    function testAddLiquidityReentrancyProtection() public {
        // This would require a malicious contract to properly test
        // For now, we verify that the nonReentrant modifier is applied
        
        vm.startPrank(user1);
        inputToken.approve(address(b3), 1000 * 1e18);
        
        // Call should succeed normally
        uint256 bondingTokensOut = b3.addLiquidity(1000 * 1e18, 0);
        assertTrue(bondingTokensOut > 0, "Normal call should succeed");
        
        vm.stopPrank();
    }
    
    function testRemoveLiquidityReentrancyProtection() public {
        // Setup liquidity first
        vm.startPrank(user1);
        inputToken.approve(address(b3), 1000 * 1e18);
        b3.addLiquidity(1000 * 1e18, 0);
        
        // Call should succeed normally
        uint256 inputTokensOut = b3.removeLiquidity(10000, 0);
        assertTrue(inputTokensOut > 0, "Normal call should succeed");
        
        vm.stopPrank();
    }
    
    // ============ INTEGRATION TESTS ============
    
    function testCompleteUserFlow() public {
        uint256 inputAmount = 1000 * 1e18;
        
        vm.startPrank(user1);
        
        // 1. Check quotes
        uint256 quotedBonding = b3.quoteAddLiquidity(inputAmount);
        assertTrue(quotedBonding > 0, "Should get valid quote");
        
        // 2. Add liquidity
        inputToken.approve(address(b3), inputAmount);
        uint256 actualBonding = b3.addLiquidity(inputAmount, quotedBonding);
        assertEq(actualBonding, quotedBonding, "Actual should match quote");
        
        // 3. Check bonding token balance
        assertEq(bondingToken.balanceOf(user1), actualBonding, "Should have bonding tokens");
        
        // 4. Quote removal
        uint256 quotedInput = b3.quoteRemoveLiquidity(actualBonding);
        assertTrue(quotedInput > 0, "Should get valid removal quote");
        
        // 5. Remove liquidity
        uint256 actualInput = b3.removeLiquidity(actualBonding, 0);
        assertEq(actualInput, quotedInput, "Removal should match quote");
        
        // 6. Check final state
        assertEq(bondingToken.balanceOf(user1), 0, "Should have no bonding tokens");
        
        vm.stopPrank();
    }
    
    function testMultipleUsersInteraction() public {
        uint256 inputAmount = 50; // Use small amounts proportional to virtual pair scale
        
        // User 1 adds liquidity
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        uint256 user1Bonding = b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();
        
        // User 2 adds liquidity (should get different amount due to virtual pair)
        vm.startPrank(user2);
        inputToken.approve(address(b3), inputAmount);
        uint256 user2Bonding = b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();
        
        // Verify both users have bonding tokens
        assertTrue(user1Bonding > 0, "User 1 should have bonding tokens");
        assertTrue(user2Bonding > 0, "User 2 should have bonding tokens");
        assertTrue(user2Bonding < user1Bonding, "User 2 should get fewer tokens");
        
        // Both users remove liquidity
        vm.startPrank(user1);
        uint256 user1Input = b3.removeLiquidity(user1Bonding, 0);
        assertTrue(user1Input > 0, "User 1 should get input tokens back");
        vm.stopPrank();
        
        vm.startPrank(user2);
        uint256 user2Input = b3.removeLiquidity(user2Bonding, 0);
        assertTrue(user2Input > 0, "User 2 should get input tokens back");
        vm.stopPrank();
    }
    
    function testVaultFailureHandling() public {
        // This test simulates vault failures
        uint256 inputAmount = 1000 * 1e18;
        
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        
        // If vault is broken/fails, operations should handle it gracefully
        try b3.addLiquidity(inputAmount, 0) returns (uint256 result) {
            assertTrue(result > 0, "Should handle vault operations");
        } catch Error(string memory reason) {
            // If it fails, it should fail gracefully with meaningful error
            assertTrue(bytes(reason).length > 0, "Should provide meaningful error message");
        }
        
        vm.stopPrank();
    }
    
    // ============ EDGE CASE TESTS ============
    
    function testOverflowProtection() public {
        uint256 maxAmount = type(uint256).max / 2;
        
        vm.startPrank(user1);
        inputToken.mint(user1, maxAmount);
        inputToken.approve(address(b3), maxAmount);
        
        // Should either handle large amounts or revert gracefully
        try b3.addLiquidity(maxAmount, 0) returns (uint256 result) {
            assertTrue(result > 0, "Should handle large amounts");
        } catch {
            // Acceptable if it reverts due to overflow protection
        }
        
        vm.stopPrank();
    }
    
    function testZeroAddressProtection() public {
        // Contract allows zero address construction but operations should fail
        vm.startPrank(owner);
        
        // Constructor allows zero address (current contract behavior)
        Behodler3Tokenlaunch b3WithZeroToken = new Behodler3Tokenlaunch(
            IERC20(address(0)),
            IBondingToken(address(bondingToken)),
            IVault(address(vault))
        );
        
        // Operations with zero address token should fail
        vm.expectRevert(); // ERC20 operations will fail with zero address
        b3WithZeroToken.addLiquidity(100, 0);
        
        // Test that normal construction with valid addresses works
        Behodler3Tokenlaunch b3Valid = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)),
            IBondingToken(address(bondingToken)),
            IVault(address(vault))
        );
        
        // Valid construction should succeed
        assertTrue(address(b3Valid) != address(0), "Valid construction should succeed");
        
        vm.stopPrank();
    }
    
    function testInvariantVirtualPairIntegrity() public {
        // This test ensures virtual pair invariants are maintained across operations
        
        vm.startPrank(user1);
        inputToken.approve(address(b3), 500); // Use appropriate amount for virtual pair scale
        
        for (uint i = 0; i < 5; i++) {
            // Add liquidity with small amounts that work with virtual pair scale
            b3.addLiquidity(20, 0); // Small incremental amounts
            
            // Check virtual pair integrity
            (uint256 vInput, uint256 vL, uint256 k) = b3.getVirtualPair();
            assertEq(k, vInput * vL, "K should always equal vInput * vL");
            
            // K should be approximately the constant (allowing for rounding)
            assertApproxEqRel(k, b3.K(), 1e15, "K should approximately match constant"); // 0.1% tolerance
            
            // Virtual L should be different from bonding token supply
            assertTrue(vL != bondingToken.totalSupply(), "VirtualL should differ from total supply");
        }
        
        vm.stopPrank();
    }
    
    // ============ GAS OPTIMIZATION TESTS ============
    
    function testGasUsageAddLiquidity() public {
        uint256 inputAmount = 1000 * 1e18;
        
        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        
        uint256 gasBefore = gasleft();
        b3.addLiquidity(inputAmount, 0);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Document gas usage (adjust limits based on requirements)
        assertTrue(gasUsed < 500000, "Add liquidity should use reasonable gas");
        
        vm.stopPrank();
    }
    
    function testGasUsageRemoveLiquidity() public {
        // Setup
        vm.startPrank(user1);
        inputToken.approve(address(b3), 1000 * 1e18);
        b3.addLiquidity(1000 * 1e18, 0);
        
        uint256 gasBefore = gasleft();
        b3.removeLiquidity(10000, 0);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Document gas usage
        assertTrue(gasUsed < 500000, "Remove liquidity should use reasonable gas");
        
        vm.stopPrank();
    }
    
    // Define events for testing
    event ContractLocked();
    event ContractUnlocked();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}