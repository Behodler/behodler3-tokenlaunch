// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ScribbleValidationContract.sol";

/**
 * @title ScribbleValidationTest
 * @notice Test suite to validate Scribble installation and instrumentation
 * @dev Demonstrates that Scribble-annotated contracts integrate with Foundry tests
 */
contract ScribbleValidationTest is Test {
    ScribbleValidationContract public contract_;

    function setUp() public {
        contract_ = new ScribbleValidationContract();
    }

    function testBasicDeposit() public {
        uint amount = 100;

        // Test the original contract (without instrumentation)
        contract_.deposit(amount);

        assertEq(contract_.balance(), amount);
        assertEq(contract_.totalDeposits(), amount);
        assertEq(contract_.userDeposits(address(this)), amount);
    }

    function testBasicWithdraw() public {
        uint amount = 100;

        // First deposit
        contract_.deposit(amount);

        // Then withdraw
        contract_.withdraw(amount);

        assertEq(contract_.balance(), 0);
        assertEq(contract_.totalDeposits(), amount); // Total deposits should remain
        assertEq(contract_.userDeposits(address(this)), 0);
    }

    function testMultipleDeposits() public {
        uint amount1 = 50;
        uint amount2 = 75;

        contract_.deposit(amount1);
        contract_.deposit(amount2);

        assertEq(contract_.balance(), amount1 + amount2);
        assertEq(contract_.totalDeposits(), amount1 + amount2);
        assertEq(contract_.userDeposits(address(this)), amount1 + amount2);
    }

    function test_RevertWhen_ZeroDeposit() public {
        // This should fail due to the require statement
        vm.expectRevert("Amount must be positive");
        contract_.deposit(0);
    }

    function test_RevertWhen_InsufficientWithdraw() public {
        // Try to withdraw without depositing first
        vm.expectRevert("Insufficient user balance");
        contract_.withdraw(100);
    }
}
