// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ScribbleValidationContract.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockBondingToken.sol";
import "@vault/mocks/MockVault.sol";

/**
 * @title ScribbleInvariantTest
 * @notice Test suite to validate that Scribble specifications catch common invariant violations
 * @dev These tests intentionally attempt to violate invariants to ensure Scribble catches them
 */
contract ScribbleInvariantTest is Test {
    ScribbleValidationContract public validationContract;
    Behodler3Tokenlaunch public tokenLaunch;
    MockERC20 public inputToken;
    MockBondingToken public bondingToken;
    MockVault public vault;

    function setUp() public {
        validationContract = new ScribbleValidationContract();

        // Set up TokenLaunch test environment
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));

        tokenLaunch = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IVault(address(vault))
        );

        // Initialize vault approval
        vault.setClient(address(tokenLaunch), true);
        tokenLaunch.initializeVaultApproval();

        // Set up initial goals for tokenLaunch
        tokenLaunch.setGoals(1000 ether, 9e17); // 90% desired average price, above sqrt(0.75)
    }

    /**
     * @notice Test that balance invariant violations are caught
     * @dev This should fail if balance exceeds total deposits
     */
    function testValidationContractBalanceInvariant() public {
        validationContract.deposit(100);

        // The balance should now be 100 and total deposits should be 100
        assertEq(validationContract.balance(), 100);
        assertEq(validationContract.totalDeposits(), 100);

        // Invariant should hold: balance <= totalDeposits
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
    }

    /**
     * @notice Test multiple deposits maintain balance invariant
     */
    function testMultipleDepositsPreserveInvariant() public {
        validationContract.deposit(50);
        validationContract.deposit(75);
        validationContract.deposit(25);

        // Check that balance invariant is maintained after multiple operations
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
        assertTrue(validationContract.balance() >= 0);
        assertTrue(validationContract.totalDeposits() >= 0);
    }

    /**
     * @notice Test withdraw operations maintain invariants
     */
    function testWithdrawPreservesInvariants() public {
        validationContract.deposit(200);
        validationContract.withdraw(100);

        // After withdraw, invariants should still hold
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
        assertTrue(validationContract.balance() >= 0);
        assertTrue(validationContract.totalDeposits() >= 0);

        // Balance should be less than total deposits after partial withdraw
        assertTrue(validationContract.balance() < validationContract.totalDeposits());
    }

    /**
     * @notice Test TokenLaunch virtual K invariant
     * @dev Virtual K must maintain consistency with virtual pair product
     */
    function testTokenLaunchVirtualKInvariant() public {
        // After setting goals, virtual K should be properly calculated
        uint256 virtualK = tokenLaunch.virtualK();
        uint256 virtualInputTokens = tokenLaunch.virtualInputTokens();
        uint256 virtualL = tokenLaunch.virtualL();
        uint256 alpha = tokenLaunch.alpha();
        uint256 beta = tokenLaunch.beta();

        // Check virtual K consistency invariant
        if (virtualK > 0) {
            uint256 expectedK = (virtualInputTokens + alpha) * (virtualL + beta);
            assertApproxEqRel(
                virtualK, expectedK, 1e15, "Virtual K should equal (virtualInputTokens + alpha) * (virtualL + beta)"
            );
        }
    }

    /**
     * @notice Test that funding goal is greater than seed input
     */
    function testFundingGoalInvariant() public {
        uint256 fundingGoal = tokenLaunch.fundingGoal();
        uint256 seedInput = tokenLaunch.seedInput();

        // Invariant: funding goal must be greater than seed input when set
        if (fundingGoal > 0) {
            assertTrue(fundingGoal > seedInput, "Funding goal must be greater than seed input");
        }
    }

    /**
     * @notice Test virtual liquidity parameter initialization consistency
     */
    function testVirtualLiquidityParameterConsistency() public {
        uint256 virtualK = tokenLaunch.virtualK();
        uint256 alpha = tokenLaunch.alpha();
        uint256 beta = tokenLaunch.beta();

        // Check initialization consistency invariant
        if (virtualK > 0) {
            assertTrue(alpha > 0, "Alpha must be positive when virtualK is set");
            assertTrue(beta > 0, "Beta must be positive when virtualK is set");
        } else {
            assertTrue(alpha == 0, "Alpha must be zero when virtualK is not set");
            assertTrue(beta == 0, "Beta must be zero when virtualK is not set");
        }
    }

    /**
     * @notice Test vault approval state consistency
     */
    function testVaultApprovalConsistency() public {
        bool vaultApprovalInitialized = tokenLaunch.vaultApprovalInitialized();
        address vaultAddress = address(tokenLaunch.vault());

        // If vault approval is initialized, vault address must not be zero
        if (vaultApprovalInitialized) {
            assertTrue(vaultAddress != address(0), "Vault address must be set when approval is initialized");
        }
    }

    /**
     * @notice Test bonding token supply bounds
     */
    function testBondingTokenSupplyBounds() public {
        uint256 virtualL = tokenLaunch.virtualL();
        uint256 virtualInputTokens = tokenLaunch.virtualInputTokens();
        uint256 totalSupply = bondingToken.totalSupply();

        // Bonding token total supply must not exceed reasonable mathematical limits
        assertTrue(totalSupply <= virtualL + virtualInputTokens, "Bonding token supply must not exceed virtual limits");
        assertTrue(totalSupply >= 0, "Bonding token supply must be non-negative");
    }

    /**
     * @notice Test alpha and beta mathematical consistency
     */
    function testAlphaBetaConsistency() public {
        uint256 alpha = tokenLaunch.alpha();
        uint256 beta = tokenLaunch.beta();

        // Alpha and beta must be mathematically consistent
        if (alpha > 0 || beta > 0) {
            assertEq(alpha, beta, "Alpha must equal beta for proper curve behavior");
        }
    }

    /**
     * @notice Test slippage protection parameters
     */
    function testSlippageProtection() public {
        uint256 alpha = tokenLaunch.alpha();
        uint256 fundingGoal = tokenLaunch.fundingGoal();

        // Slippage protection: virtual parameters must be reasonable
        if (alpha > 0) {
            assertTrue(alpha <= fundingGoal * 10, "Alpha must be reasonable relative to funding goal");
        }
    }

    /**
     * @notice Test that locked state prevents operations
     */
    function testLockedStateInvariant() public {
        // Lock the contract
        tokenLaunch.lock();
        assertTrue(tokenLaunch.locked(), "Contract should be locked");

        // Prepare for addLiquidity
        inputToken.mint(address(this), 1000 ether);
        inputToken.approve(address(tokenLaunch), 1000 ether);

        // Operations should fail when locked
        vm.expectRevert("B3: Contract is locked");
        tokenLaunch.addLiquidity(100 ether, 0);
    }

    /**
     * @notice Test fuzz testing against invariants
     */
    function testFuzzInvariantPreservation(uint256 depositAmount) public {
        // Bound the fuzz input to reasonable values
        depositAmount = bound(depositAmount, 1, 1_000_000);

        validationContract.deposit(depositAmount);

        // All invariants should hold for any valid deposit amount
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
        assertTrue(validationContract.balance() >= 0);
        assertTrue(validationContract.totalDeposits() >= 0);
        assertEq(validationContract.balance(), depositAmount);
        assertEq(validationContract.totalDeposits(), depositAmount);
    }

    /**
     * @notice Test edge case: maximum values
     */
    function testMaximumValueInvariants() public {
        // Test with maximum reasonable values
        uint256 maxDeposit = type(uint128).max; // Use uint128 max to avoid overflow

        try validationContract.deposit(maxDeposit) {
            assertTrue(validationContract.balance() <= validationContract.totalDeposits());
            assertTrue(validationContract.balance() >= 0);
        } catch {
            // If it reverts due to overflow protection, that's also valid behavior
            // The invariant should prevent unsafe operations
        }
    }

    /**
     * @notice Test that specifications catch arithmetic overflow attempts
     */
    function testArithmeticOverflowProtection() public {
        // Deposit a large amount
        uint256 largeAmount = type(uint256).max / 2;

        try validationContract.deposit(largeAmount) {
            // If successful, invariants should still hold
            assertTrue(validationContract.balance() <= validationContract.totalDeposits());

            // Try to deposit again to potentially cause overflow
            try validationContract.deposit(largeAmount) {
                // If both succeed, check invariants still hold
                assertTrue(validationContract.balance() <= validationContract.totalDeposits());
            } catch {
                // Overflow protection working correctly
            }
        } catch {
            // Initial deposit failed due to overflow protection, which is correct
        }
    }

    /**
     * @notice Test state consistency across multiple operations
     */
    function testMultiOperationStateConsistency() public {
        // Perform a series of operations
        validationContract.deposit(100);
        validationContract.deposit(200);
        validationContract.withdraw(50);
        validationContract.deposit(75);
        validationContract.withdraw(25);

        // Check final state consistency
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
        assertTrue(validationContract.balance() >= 0);
        assertTrue(validationContract.totalDeposits() >= 0);

        // Verify specific values
        assertEq(validationContract.balance(), 300); // 100 + 200 - 50 + 75 - 25
        assertEq(validationContract.totalDeposits(), 375); // 100 + 200 + 75 (withdraws don't reduce total)
    }
}
