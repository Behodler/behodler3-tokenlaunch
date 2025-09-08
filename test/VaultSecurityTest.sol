// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/mocks/MockVault.sol";
import "../src/mocks/MockERC20.sol";
import "../src/Vault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VaultSecurityTest
 * @notice Comprehensive test suite for Vault contract security features
 * @dev Tests all access control mechanisms, owner functions, and security edge cases
 */
contract VaultSecurityTest is Test {
    MockVault public vault;
    MockERC20 public token;
    
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public bondingCurve = makeAddr("bondingCurve");
    address public attacker = makeAddr("attacker");
    
    function setUp() public {
        // Deploy contracts
        token = new MockERC20("Test Token", "TEST", 18);
        vault = new MockVault(owner);
        
        // Setup initial tokens
        token.mint(user1, 1000000 * 1e18);
        token.mint(user2, 1000000 * 1e18);
        token.mint(attacker, 1000000 * 1e18);
        token.mint(bondingCurve, 10000000 * 1e18); // Give tokens to bonding curve for tests
        
        // Set bonding curve address as owner
        vm.prank(owner);
        vault.setBondingCurve(bondingCurve);
        
        // Give bonding curve approval for its own tokens
        vm.prank(bondingCurve);
        token.approve(address(vault), type(uint256).max);
    }
    
    // ============ BONDING CURVE ACCESS CONTROL TESTS ============
    
    function testOnlyBondingCurveCanDeposit() public {
        // Arrange
        uint256 amount = 1000 * 1e18;
        
        // Act & Assert - Only bonding curve can deposit
        vm.prank(bondingCurve);
        vault.deposit(address(token), amount, bondingCurve); // Deposit to bonding curve itself
        
        // Verify deposit worked
        assertEq(vault.balanceOf(address(token), bondingCurve), amount);
    }
    
    function testUnauthorizedDepositReverts() public {
        // Arrange
        uint256 amount = 1000 * 1e18;
        vm.prank(user1);
        token.approve(address(vault), amount);
        
        // Act & Assert - User cannot deposit directly
        vm.prank(user1);
        vm.expectRevert("Vault: unauthorized, only bonding curve");
        vault.deposit(address(token), amount, user1);
        
        // Act & Assert - Attacker cannot deposit
        vm.prank(attacker);
        vm.expectRevert("Vault: unauthorized, only bonding curve");
        vault.deposit(address(token), amount, user1);
        
        // Act & Assert - Owner cannot deposit (unless they are also bonding curve)
        vm.prank(owner);
        vm.expectRevert("Vault: unauthorized, only bonding curve");
        vault.deposit(address(token), amount, user1);
    }
    
    function testOnlyBondingCurveCanWithdraw() public {
        // Arrange - First deposit some tokens
        uint256 depositAmount = 1000 * 1e18;
        
        vm.prank(bondingCurve);
        vault.deposit(address(token), depositAmount, bondingCurve); // Deposit to bonding curve itself
        
        // Act & Assert - Only bonding curve can withdraw
        uint256 withdrawAmount = 500 * 1e18;
        vm.prank(bondingCurve);
        vault.withdraw(address(token), withdrawAmount, user2);
        
        // Verify withdrawal worked
        assertEq(vault.balanceOf(address(token), bondingCurve), depositAmount - withdrawAmount);
        assertEq(token.balanceOf(user2), 1000000 * 1e18 + withdrawAmount);
    }
    
    function testUnauthorizedWithdrawReverts() public {
        // Arrange - First deposit some tokens
        uint256 depositAmount = 1000 * 1e18;
        
        vm.prank(bondingCurve);
        vault.deposit(address(token), depositAmount, bondingCurve);
        
        uint256 withdrawAmount = 500 * 1e18;
        
        // Act & Assert - User cannot withdraw directly
        vm.prank(user1);
        vm.expectRevert("Vault: unauthorized, only bonding curve");
        vault.withdraw(address(token), withdrawAmount, user1);
        
        // Act & Assert - Attacker cannot withdraw
        vm.prank(attacker);
        vm.expectRevert("Vault: unauthorized, only bonding curve");
        vault.withdraw(address(token), withdrawAmount, attacker);
        
        // Act & Assert - Owner cannot withdraw (unless they are also bonding curve)
        vm.prank(owner);
        vm.expectRevert("Vault: unauthorized, only bonding curve");
        vault.withdraw(address(token), withdrawAmount, owner);
    }
    
    // ============ OWNER ACCESS CONTROL TESTS ============
    
    function testOnlyOwnerCanSetBondingCurve() public {
        address newBondingCurve = makeAddr("newBondingCurve");
        
        // Act & Assert - Owner can set bonding curve
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit Vault.BondingCurveSet(bondingCurve, newBondingCurve);
        vault.setBondingCurve(newBondingCurve);
        
        // Verify change
        assertEq(vault.bondingCurve(), newBondingCurve);
    }
    
    function testUnauthorizedSetBondingCurveReverts() public {
        address newBondingCurve = makeAddr("newBondingCurve");
        
        // Act & Assert - User cannot set bonding curve
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vault.setBondingCurve(newBondingCurve);
        
        // Act & Assert - Attacker cannot set bonding curve
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.setBondingCurve(newBondingCurve);
        
        // Act & Assert - Bonding curve itself cannot change the setting
        vm.prank(bondingCurve);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bondingCurve));
        vault.setBondingCurve(newBondingCurve);
        
        // Verify no change occurred
        assertEq(vault.bondingCurve(), bondingCurve);
    }
    
    function testOnlyOwnerCanEmergencyWithdraw() public {
        uint256 amount = 100 * 1e18;
        
        // Act & Assert - Owner can call emergency withdraw
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Vault.EmergencyWithdraw(owner, amount);
        vault.emergencyWithdraw(amount);
    }
    
    function testUnauthorizedEmergencyWithdrawReverts() public {
        uint256 amount = 100 * 1e18;
        
        // Act & Assert - User cannot emergency withdraw
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vault.emergencyWithdraw(amount);
        
        // Act & Assert - Attacker cannot emergency withdraw
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.emergencyWithdraw(amount);
        
        // Act & Assert - Bonding curve cannot emergency withdraw
        vm.prank(bondingCurve);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bondingCurve));
        vault.emergencyWithdraw(amount);
    }
    
    // ============ INPUT VALIDATION TESTS ============
    
    function testSetBondingCurveZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert("Vault: bonding curve cannot be zero address");
        vault.setBondingCurve(address(0));
    }
    
    function testEmergencyWithdrawZeroAmountReverts() public {
        vm.prank(owner);
        vm.expectRevert("Vault: amount must be greater than zero");
        vault.emergencyWithdraw(0);
    }
    
    function testDepositValidation() public {
        uint256 amount = 1000 * 1e18;
        vm.prank(user1);
        token.approve(address(vault), amount);
        
        vm.startPrank(bondingCurve);
        
        // Zero token address should revert
        vm.expectRevert("MockVault: token is zero address");
        vault.deposit(address(0), amount, user1);
        
        // Zero amount should revert
        vm.expectRevert("MockVault: amount is zero");
        vault.deposit(address(token), 0, user1);
        
        // Zero recipient address should revert
        vm.expectRevert("MockVault: recipient is zero address");
        vault.deposit(address(token), amount, address(0));
        
        vm.stopPrank();
    }
    
    function testWithdrawValidation() public {
        // First deposit some tokens
        uint256 depositAmount = 1000 * 1e18;
        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        
        vm.prank(bondingCurve);
        vault.deposit(address(token), depositAmount, bondingCurve);
        
        vm.startPrank(bondingCurve);
        
        // Zero token address should revert
        vm.expectRevert("MockVault: token is zero address");
        vault.withdraw(address(0), 500 * 1e18, user1);
        
        // Zero amount should revert
        vm.expectRevert("MockVault: amount is zero");
        vault.withdraw(address(token), 0, user1);
        
        // Zero recipient address should revert
        vm.expectRevert("MockVault: recipient is zero address");
        vault.withdraw(address(token), 500 * 1e18, address(0));
        
        vm.stopPrank();
    }
    
    // ============ EDGE CASE AND INTEGRATION TESTS ============
    
    function testBondingCurveCanBeChanged() public {
        address newBondingCurve = makeAddr("newBondingCurve");
        
        // Setup initial deposit with old bonding curve
        uint256 amount = 1000 * 1e18;
        
        vm.prank(bondingCurve);
        vault.deposit(address(token), amount, user1);
        
        // Change bonding curve
        vm.prank(owner);
        vault.setBondingCurve(newBondingCurve);
        
        // Give new bonding curve tokens and approval
        token.mint(newBondingCurve, 1000000 * 1e18);
        vm.prank(newBondingCurve);
        token.approve(address(vault), type(uint256).max);
        
        // Old bonding curve should no longer work for new deposits
        vm.prank(bondingCurve);
        vm.expectRevert("Vault: unauthorized, only bonding curve");
        vault.deposit(address(token), 100 * 1e18, bondingCurve);
        
        // New bonding curve should work for new deposits
        vm.prank(newBondingCurve);
        vault.deposit(address(token), 100 * 1e18, newBondingCurve);
        
        // Verify state
        assertEq(vault.balanceOf(address(token), bondingCurve), amount); // Old balance unchanged
        assertEq(vault.balanceOf(address(token), newBondingCurve), 100 * 1e18); // New deposit
    }
    
    function testOwnershipTransferMaintainsAccessControl() public {
        address newOwner = makeAddr("newOwner");
        
        // Transfer ownership
        vm.prank(owner);
        vault.transferOwnership(newOwner);
        
        // Old owner should no longer be able to set bonding curve
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vault.setBondingCurve(makeAddr("anotherCurve"));
        
        // New owner should be able to set bonding curve
        address anotherCurve = makeAddr("anotherCurve");
        vm.prank(newOwner);
        vault.setBondingCurve(anotherCurve);
        
        assertEq(vault.bondingCurve(), anotherCurve);
    }
    
    function testMultipleTokensAccessControl() public {
        // Deploy second token
        MockERC20 token2 = new MockERC20("Test Token 2", "TEST2", 18);
        token2.mint(user1, 1000000 * 1e18);
        token2.mint(bondingCurve, 10000000 * 1e18);
        
        uint256 amount1 = 500 * 1e18;
        uint256 amount2 = 300 * 1e18;
        
        // Give bonding curve approval for second token
        vm.prank(bondingCurve);
        token2.approve(address(vault), type(uint256).max);
        
        // Only bonding curve can deposit both tokens
        vm.startPrank(bondingCurve);
        vault.deposit(address(token), amount1, bondingCurve);
        vault.deposit(address(token2), amount2, bondingCurve);
        vm.stopPrank();
        
        // Verify balances
        assertEq(vault.balanceOf(address(token), bondingCurve), amount1);
        assertEq(vault.balanceOf(address(token2), bondingCurve), amount2);
        
        // Users still cannot access directly for either token
        vm.prank(user1);
        vm.expectRevert("Vault: unauthorized, only bonding curve");
        vault.withdraw(address(token), 100 * 1e18, user1);
        
        vm.prank(user1);
        vm.expectRevert("Vault: unauthorized, only bonding curve");
        vault.withdraw(address(token2), 100 * 1e18, user1);
    }
    
    // ============ EVENTS TESTING ============
    
    function testBondingCurveSetEventEmission() public {
        address newCurve = makeAddr("newCurve");
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit Vault.BondingCurveSet(bondingCurve, newCurve);
        vault.setBondingCurve(newCurve);
    }
    
    function testEmergencyWithdrawEventEmission() public {
        uint256 amount = 1000;
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit Vault.EmergencyWithdraw(owner, amount);
        vault.emergencyWithdraw(amount);
    }
    
    // ============ INTEGRATION WITH EXISTING FUNCTIONALITY ============
    
    function testSecurityDoesNotBreakNormalOperations() public {
        uint256 amount = 1000 * 1e18;
        
        // Bonding curve deposits (approval already set in setUp)
        vm.prank(bondingCurve);
        vault.deposit(address(token), amount, bondingCurve);
        
        assertEq(vault.balanceOf(address(token), bondingCurve), amount);
        assertEq(vault.getTotalDeposits(address(token)), amount);
        
        // Bonding curve withdraws
        uint256 withdrawAmount = 600 * 1e18;
        vm.prank(bondingCurve);
        vault.withdraw(address(token), withdrawAmount, user2);
        
        assertEq(vault.balanceOf(address(token), bondingCurve), amount - withdrawAmount);
        assertEq(token.balanceOf(user2), 1000000 * 1e18 + withdrawAmount);
        assertEq(vault.getTotalDeposits(address(token)), amount - withdrawAmount);
    }
}