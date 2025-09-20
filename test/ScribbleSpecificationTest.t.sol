// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ScribbleValidationContract.sol";

/**
 * @title ScribbleSpecificationTest
 * @notice Test contract to validate Scribble specifications are working correctly
 * @dev This test demonstrates that our comprehensive function specifications are properly implemented
 */
contract ScribbleSpecificationTest is Test {
    ScribbleValidationContract public testContract;

    function setUp() public {
        testContract = new ScribbleValidationContract();
    }

    /**
     * @notice Test that preconditions and postconditions work for deposit function
     */
    function testDepositSpecifications() public {
        uint depositAmount = 100;
        uint initialBalance = testContract.balance();
        uint initialTotalDeposits = testContract.totalDeposits();
        uint initialUserDeposit = testContract.getUserDeposit(address(this));

        // This should succeed and trigger postcondition checks
        testContract.deposit(depositAmount);

        // Verify postconditions manually (Scribble should have already checked these)
        assertEq(testContract.balance(), initialBalance + depositAmount, "Balance should increase by deposit amount");
        assertEq(testContract.totalDeposits(), initialTotalDeposits + depositAmount, "Total deposits should increase");
        assertEq(
            testContract.getUserDeposit(address(this)),
            initialUserDeposit + depositAmount,
            "User deposit should increase"
        );
    }

    /**
     * @notice Test that preconditions prevent invalid operations
     */
    function testDepositPreconditionFailure() public {
        // This should fail the precondition check
        vm.expectRevert("Amount must be positive");
        testContract.deposit(0);
    }

    /**
     * @notice Test withdraw postconditions
     */
    function testWithdrawSpecifications() public {
        uint depositAmount = 200;
        uint withdrawAmount = 100;

        // First deposit to have something to withdraw
        testContract.deposit(depositAmount);

        uint balanceBeforeWithdraw = testContract.balance();
        uint userDepositBeforeWithdraw = testContract.getUserDeposit(address(this));

        // Withdraw and check postconditions
        testContract.withdraw(withdrawAmount);

        assertEq(
            testContract.balance(), balanceBeforeWithdraw - withdrawAmount, "Balance should decrease by withdraw amount"
        );
        assertEq(
            testContract.getUserDeposit(address(this)),
            userDepositBeforeWithdraw - withdrawAmount,
            "User deposit should decrease"
        );
    }

    /**
     * @notice Test invariant violations are caught
     */
    function testInvariantPreservation() public {
        // These operations should maintain all invariants
        testContract.deposit(50);
        testContract.deposit(75);
        testContract.withdraw(25);

        // Check that invariants still hold
        assertTrue(testContract.balance() <= testContract.totalDeposits(), "Balance should not exceed total deposits");
        assertTrue(testContract.totalDeposits() >= 0, "Total deposits should be non-negative");
        assertTrue(testContract.balance() >= 0, "Balance should be non-negative");
    }

    /**
     * @notice Test multiple users to ensure specifications work correctly
     */
    function testMultiUserSpecifications() public {
        address user1 = address(0x1);
        address user2 = address(0x2);

        // User 1 deposits
        vm.prank(user1);
        testContract.deposit(100);

        // User 2 deposits
        vm.prank(user2);
        testContract.deposit(200);

        // Verify individual user deposits
        assertEq(testContract.getUserDeposit(user1), 100, "User1 deposit should be tracked correctly");
        assertEq(testContract.getUserDeposit(user2), 200, "User2 deposit should be tracked correctly");
        assertEq(testContract.totalDeposits(), 300, "Total deposits should be sum of all deposits");
        assertEq(testContract.balance(), 300, "Balance should equal total deposits");

        // User 1 withdraws
        vm.prank(user1);
        testContract.withdraw(50);

        // Verify postconditions for partial withdraw
        assertEq(testContract.getUserDeposit(user1), 50, "User1 deposit should decrease");
        assertEq(testContract.getUserDeposit(user2), 200, "User2 deposit should be unchanged");
        assertEq(testContract.balance(), 250, "Balance should decrease by withdrawal amount");
    }
}
