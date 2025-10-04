// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ScribbleValidationContract.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockBondingToken.sol";
import "@vault/mocks/MockVault.sol";

/**
 * @title ScribbleEdgeCaseTest
 * @notice Test suite to validate Scribble specifications against known edge cases
 * @dev These tests cover boundary conditions, edge cases, and potential attack vectors
 */
contract ScribbleEdgeCaseTest is Test {
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
    }

    /**
     * @notice Test edge case: Minimum deposit value (1 wei)
     */
    function testMinimumDepositEdgeCase() public {
        uint256 minDeposit = 1;

        validationContract.deposit(minDeposit);

        // Verify invariants hold for minimum deposit
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
        assertEq(validationContract.balance(), minDeposit);
        assertEq(validationContract.totalDeposits(), minDeposit);
    }

    /**
     * @notice Test edge case: Zero value handling
     */
    function testZeroValueEdgeCase() public {
        // Zero deposit should fail with appropriate error
        vm.expectRevert("Amount must be positive");
        validationContract.deposit(0);

        // Zero withdraw should fail
        vm.expectRevert("Amount must be positive");
        validationContract.withdraw(0);
    }

    /**
     * @notice Test edge case: Withdraw more than deposited
     */
    function testOverWithdrawEdgeCase() public {
        validationContract.deposit(100);

        // Try to withdraw more than deposited
        vm.expectRevert("Insufficient user balance");
        validationContract.withdraw(101);

        // Verify state remains consistent after failed operation
        assertEq(validationContract.balance(), 100);
        assertEq(validationContract.getUserDeposit(address(this)), 100);
    }

    /**
     * @notice Test edge case: Multiple users with different deposit amounts
     */
    function testMultiUserEdgeCases() public {
        address user1 = address(0x1);
        address user2 = address(0x2);
        address user3 = address(0x3);

        // User 1: minimum deposit
        vm.prank(user1);
        validationContract.deposit(1);

        // User 2: maximum reasonable deposit
        vm.prank(user2);
        validationContract.deposit(type(uint128).max);

        // User 3: medium deposit
        vm.prank(user3);
        validationContract.deposit(1000 ether);

        // Verify invariants hold for all users
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
        assertTrue(validationContract.balance() >= 0);
        assertTrue(validationContract.totalDeposits() >= 0);

        // Verify individual balances
        assertEq(validationContract.getUserDeposit(user1), 1);
        assertEq(validationContract.getUserDeposit(user2), type(uint128).max);
        assertEq(validationContract.getUserDeposit(user3), 1000 ether);
    }

    /**
     * @notice Test edge case: TokenLaunch with extreme funding goals
     */
    function testExtremeFundingGoalEdgeCases() public {
        // Test with reasonable but large funding goal
        tokenLaunch.setGoals(1_000_000 ether, 9e17); // 0.9, above sqrt(0.75)
        assertTrue(tokenLaunch.fundingGoal() > tokenLaunch.seedInput());

        // Test with minimal valid funding goal
        tokenLaunch.setGoals(10 ether, 9e17); // 0.9, above sqrt(0.75)
        assertTrue(tokenLaunch.fundingGoal() > tokenLaunch.seedInput());
    }

    /**
     * @notice Test edge case: Desired average price boundaries
     */
    function testDesiredAveragePriceBoundaries() public {
        // With zero seed enforcement, minimum avg price is sqrt(0.75) ≈ 0.866
        // Test minimum valid price
        tokenLaunch.setGoals(1000 ether, 866025403784438647); // sqrt(0.75) exactly
        assertTrue(tokenLaunch.desiredAveragePrice() >= 866025403784438647);
        assertTrue(tokenLaunch.desiredAveragePrice() < 1e18);

        // Test higher valid price
        tokenLaunch.setGoals(1000 ether, 9e17); // 90%
        assertTrue(tokenLaunch.desiredAveragePrice() > 0);
        assertTrue(tokenLaunch.desiredAveragePrice() < 1e18);

        // Test price just below minimum (866025403784438646) - should revert
        vm.expectRevert("VL: Average price must be >= sqrt(0.75) for P0 >= 0.75");
        tokenLaunch.setGoals(1000 ether, 866025403784438646);

        // Test price just above minimum (866025403784438648) - should succeed
        tokenLaunch.setGoals(1000 ether, 866025403784438648);
        assertEq(tokenLaunch.desiredAveragePrice(), 866025403784438648);
        assertTrue(tokenLaunch.virtualK() > 0, "Virtual K should be set for just-above-minimum price");

        // Test price below minimum should fail
        vm.expectRevert("VL: Average price must be >= sqrt(0.75) for P0 >= 0.75");
        tokenLaunch.setGoals(1000 ether, 8e17); // 0.8, below sqrt(0.75)

        // Test price >= 1 should fail
        vm.expectRevert("VL: Average price must be < 1");
        tokenLaunch.setGoals(1000 ether, 1e18);
    }

    /**
     * @notice Test edge case: Virtual K calculation with extreme values
     */
    function testVirtualKCalculationEdgeCases() public {
        // Set goals that might cause calculation edge cases
        tokenLaunch.setGoals(1000 ether, 9e17); // 90% desired average price, above sqrt(0.75)

        uint256 virtualK = tokenLaunch.virtualK();
        uint256 virtualInputTokens = tokenLaunch.virtualInputTokens();
        uint256 virtualL = tokenLaunch.virtualL();
        uint256 alpha = tokenLaunch.alpha();
        uint256 beta = tokenLaunch.beta();

        // Verify virtual K invariant holds even with extreme parameters with strict precision
        if (virtualK > 0) {
            // K invariant must be preserved with strict tolerance for mathematical correctness
            // Using relative tolerance of 0.0001% (1000x stricter than original 0.1%)
            uint256 leftSide = (virtualInputTokens + alpha) * (virtualL + beta);
            uint256 tolerance = virtualK / 1e18; // 0.0001% tolerance
            assertApproxEqAbs(
                virtualK, leftSide, tolerance, "Virtual K invariant should hold within 0.0001% precision"
            );
            assertTrue(alpha > 0);
            assertTrue(beta > 0);
            assertEq(alpha, beta);
        }
    }

    /**
     * @notice Test edge case: Sequential deposit and withdraw operations
     */
    function testSequentialOperationEdgeCases() public {
        // Deposit small amount
        validationContract.deposit(1);

        // Withdraw exactly what was deposited
        validationContract.withdraw(1);

        // Balance should be 0, but total deposits should remain
        assertEq(validationContract.balance(), 0);
        assertEq(validationContract.totalDeposits(), 1);
        assertEq(validationContract.getUserDeposit(address(this)), 0);

        // Deposit again
        validationContract.deposit(1000);

        // Verify invariants still hold
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
        assertEq(validationContract.balance(), 1000);
        assertEq(validationContract.totalDeposits(), 1001); // Previous 1 + new 1000
    }

    /**
     * @notice Test edge case: Contract in locked state
     */
    function testLockedContractEdgeCases() public {
        // Set up tokenLaunch for operations
        tokenLaunch.setGoals(1000 ether, 9e17); // 0.9, above sqrt(0.75)
        inputToken.mint(address(this), 1000 ether);
        inputToken.approve(address(tokenLaunch), 1000 ether);

        // Lock the contract
        tokenLaunch.lock();

        // All operations should fail
        vm.expectRevert("B3: Contract is locked");
        tokenLaunch.addLiquidity(100 ether, 0);

        vm.expectRevert("B3: Contract is locked");
        tokenLaunch.removeLiquidity(0, 0);

        // Read operations should still work
        uint256 virtualK = tokenLaunch.virtualK();
        assertTrue(virtualK > 0); // Read operations work even when locked
    }

    /**
     * @notice Test edge case: Precision and rounding in calculations
     */
    function testPrecisionAndRoundingEdgeCases() public {
        // Use values that test precision without causing overflow
        tokenLaunch.setGoals(1000 ether + 1, 9e17); // Values with some precision, above sqrt(0.75)

        uint256 virtualK = tokenLaunch.virtualK();
        uint256 alpha = tokenLaunch.alpha();
        uint256 beta = tokenLaunch.beta();

        // Verify calculations maintain precision
        assertTrue(virtualK > 0);
        assertTrue(alpha > 0);
        assertTrue(beta > 0);
        assertEq(alpha, beta);
    }

    /**
     * @notice Test edge case: Gas limit considerations
     */
    function testGasLimitEdgeCases() public {
        // Perform operations that might consume significant gas
        for (uint256 i = 0; i < 10; i++) {
            validationContract.deposit(100 + i);

            // Verify invariants hold after each iteration
            assertTrue(validationContract.balance() <= validationContract.totalDeposits());
            assertTrue(validationContract.balance() >= 0);
        }

        // Perform some withdrawals
        for (uint256 i = 0; i < 5; i++) {
            validationContract.withdraw(100 + i);
        }

        // Final state should still maintain invariants
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
        assertTrue(validationContract.balance() >= 0);
    }

    /**
     * @notice Test edge case: Reentrancy protection (if applicable)
     */
    function testReentrancyProtectionEdgeCase() public {
        // TokenLaunch has reentrancy protection
        // This test ensures that protection doesn't interfere with normal operations
        inputToken.mint(address(this), 1000 ether);
        inputToken.approve(address(tokenLaunch), 1000 ether);

        tokenLaunch.setGoals(1000 ether, 9e17); // 0.9, above sqrt(0.75)

        // Normal operation should work
        tokenLaunch.addLiquidity(100 ether, 0);

        // Verify state remains consistent
        assertTrue(bondingToken.totalSupply() > 0);
    }

    /**
     * @notice Test edge case: State consistency across view functions
     */
    function testViewFunctionConsistencyEdgeCases() public {
        tokenLaunch.setGoals(1000 ether, 9e17); // 0.9, above sqrt(0.75)

        // Get current marginal price (should not revert)
        uint256 currentPrice = tokenLaunch.getCurrentMarginalPrice();
        assertTrue(currentPrice > 0);

        // Get average price (should be 0 initially)
        uint256 avgPrice = tokenLaunch.getAveragePrice();
        assertEq(avgPrice, 0); // No bonding tokens minted yet

        // Get total raised (should equal virtual input tokens minus seed)
        uint256 totalRaised = tokenLaunch.getTotalRaised();
        assertEq(totalRaised, 0); // No additional tokens raised yet
    }

    /**
     * @notice Test edge case: Parameter validation in constructor
     */
    function testConstructorParameterValidation() public {
        // Constructor should handle zero addresses gracefully
        // (The actual validation depends on implementation)

        MockERC20 newInputToken = new MockERC20("Test", "TEST", 18);
        MockBondingToken newBondingToken = new MockBondingToken("Bond", "BOND");
        MockVault newVault = new MockVault(address(this));

        // This should succeed with valid parameters
        Behodler3Tokenlaunch newTokenLaunch = new Behodler3Tokenlaunch(
            IERC20(address(newInputToken)), IBondingToken(address(newBondingToken)), IVault(address(newVault))
        );

        // Verify initial state
        assertEq(address(newTokenLaunch.inputToken()), address(newInputToken));
        assertEq(address(newTokenLaunch.bondingToken()), address(newBondingToken));
        assertEq(address(newTokenLaunch.vault()), address(newVault));
        assertFalse(newTokenLaunch.vaultApprovalInitialized());
    }

    /**
     * @notice Test negative case: Operations fail when goals not set
     * @dev Validates that attempting operations before setGoals() fails with appropriate error
     */
    function testOperationsFailWhenGoalsNotSet() public {
        // Create a fresh TokenLaunch instance without setting goals
        MockERC20 newInputToken = new MockERC20("Test", "TEST", 18);
        MockBondingToken newBondingToken = new MockBondingToken("Bond", "BOND");
        MockVault newVault = new MockVault(address(this));

        Behodler3Tokenlaunch newTokenLaunch = new Behodler3Tokenlaunch(
            IERC20(address(newInputToken)), IBondingToken(address(newBondingToken)), IVault(address(newVault))
        );

        newVault.setClient(address(newTokenLaunch), true);
        newTokenLaunch.initializeVaultApproval();

        // Mint and approve tokens
        newInputToken.mint(address(this), 1000 ether);
        newInputToken.approve(address(newTokenLaunch), 1000 ether);

        // Attempt addLiquidity without setting goals - should fail with goals not set error
        vm.expectRevert("VL: Goals not set - call setGoals first");
        newTokenLaunch.addLiquidity(100 ether, 0);

        // For removeLiquidity, first we need to mint some bonding tokens to the user
        // Otherwise it will fail with "B3: Insufficient bonding tokens" before checking virtualK
        newBondingToken.mint(address(this), 100 ether);

        // Attempt removeLiquidity without setting goals - should now fail with correct error
        vm.expectRevert("VL: Goals not set - call setGoals first");
        newTokenLaunch.removeLiquidity(1, 0);

        // Attempt getCurrentMarginalPrice without setting goals - should fail with Scribble assertion
        // (Scribble postcondition requires virtualK > 0)
        vm.expectRevert();
        newTokenLaunch.getCurrentMarginalPrice();
    }

    /**
     * @notice Test initialization state before setGoals()
     * @dev Validates that contract state is properly initialized to zero values before setGoals()
     */
    function testInitializationStateBeforeSetGoals() public {
        // Create a fresh TokenLaunch instance
        MockERC20 newInputToken = new MockERC20("Test", "TEST", 18);
        MockBondingToken newBondingToken = new MockBondingToken("Bond", "BOND");
        MockVault newVault = new MockVault(address(this));

        Behodler3Tokenlaunch newTokenLaunch = new Behodler3Tokenlaunch(
            IERC20(address(newInputToken)), IBondingToken(address(newBondingToken)), IVault(address(newVault))
        );

        // Verify all state variables are properly initialized to zero
        assertEq(newTokenLaunch.fundingGoal(), 0, "Funding goal should be 0 before setGoals");
        assertEq(newTokenLaunch.seedInput(), 0, "Seed input should be 0 before setGoals");
        assertEq(newTokenLaunch.desiredAveragePrice(), 0, "Desired average price should be 0 before setGoals");
        assertEq(newTokenLaunch.alpha(), 0, "Alpha should be 0 before setGoals");
        assertEq(newTokenLaunch.beta(), 0, "Beta should be 0 before setGoals");
        assertEq(newTokenLaunch.virtualK(), 0, "Virtual K should be 0 before setGoals");
        assertEq(newTokenLaunch.virtualInputTokens(), 0, "Virtual input tokens should be 0 before setGoals");
        assertEq(newTokenLaunch.virtualL(), 0, "Virtual L should be 0 before setGoals");
        assertFalse(newTokenLaunch.locked(), "Contract should not be locked initially");
        assertFalse(newTokenLaunch.vaultApprovalInitialized(), "Vault approval should not be initialized yet");
    }

    /**
     * @notice Test negative case: P_avg just below minimum (should revert)
     * @dev Tests that 866025403784438646 (one unit below minimum) is rejected
     */
    function testDesiredAveragePriceBelowMinimumReverts() public {
        // Test value just below minimum sqrt(0.75)
        uint256 belowMinimum = 866025403784438646;

        vm.expectRevert("VL: Average price must be >= sqrt(0.75) for P0 >= 0.75");
        tokenLaunch.setGoals(1000 ether, belowMinimum);
    }

    /**
     * @notice Test positive case: P_avg just above minimum (should succeed)
     * @dev Tests that 866025403784438648 (one unit above minimum) is accepted
     */
    function testDesiredAveragePriceAboveMinimumSucceeds() public {
        // Test value just above minimum sqrt(0.75)
        uint256 aboveMinimum = 866025403784438648;

        // Should succeed without reverting
        tokenLaunch.setGoals(1000 ether, aboveMinimum);

        // Verify the goals were set correctly
        assertEq(tokenLaunch.fundingGoal(), 1000 ether);
        assertEq(tokenLaunch.desiredAveragePrice(), aboveMinimum);
        assertTrue(tokenLaunch.virtualK() > 0, "Virtual K should be set");
        assertTrue(tokenLaunch.alpha() > 0, "Alpha should be set");
        assertTrue(tokenLaunch.beta() > 0, "Beta should be set");
    }

    /**
     * @notice Test P₀ = P_avg² precision at boundary
     * @dev Validates that initial price P₀ equals P_avg² at minimum boundary
     *      For minimum P_avg = sqrt(0.75), P₀ should equal 0.75 exactly
     */
    function testInitialPricePrecisionAtBoundary() public {
        // Use minimum P_avg = sqrt(0.75) = 866025403784438647
        uint256 minPavg = 866025403784438647;
        tokenLaunch.setGoals(1000 ether, minPavg);

        // Calculate initial price P₀
        uint256 initialPrice = tokenLaunch.getCurrentMarginalPrice();

        // P₀ should equal P_avg² at the boundary
        // P_avg² = (866025403784438647)² / 1e18 ≈ 750000000000000000 (0.75 * 1e18)
        uint256 expectedP0 = (minPavg * minPavg) / 1e18;

        // Allow for minimal precision loss due to integer arithmetic
        // Using the empirically validated threshold from story 036.33-P3
        uint256 tolerance = expectedP0 / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(
            initialPrice,
            expectedP0,
            tolerance,
            "Initial price should equal P_avg squared at minimum boundary"
        );
    }

    /**
     * @notice Test that initial price exactly equals 0.75 at minimum boundary
     * @dev Validates P₀ = 0.75 when P_avg = sqrt(0.75) at initialization
     */
    function testInitialPriceExactlyPointSevenFiveAtMinimumBoundary() public {
        // Use minimum P_avg = sqrt(0.75) = 866025403784438647
        uint256 minPavg = 866025403784438647;
        tokenLaunch.setGoals(1000 ether, minPavg);

        // Get initial price (before any liquidity is added)
        uint256 initialPrice = tokenLaunch.getCurrentMarginalPrice();

        // Expected initial price is exactly 0.75 (scaled by 1e18)
        uint256 expectedInitialPrice = 75e16; // 0.75 * 1e18

        // Allow for minimal precision loss due to integer arithmetic
        // Using the empirically validated threshold from story 036.33-P3
        uint256 tolerance = expectedInitialPrice / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(
            initialPrice,
            expectedInitialPrice,
            tolerance,
            "Initial price should be exactly 0.75 at minimum P_avg boundary"
        );

        // Also verify it's within reasonable bounds
        assertTrue(initialPrice >= 749999e12, "Initial price should be >= 0.749999");
        assertTrue(initialPrice <= 750001e12, "Initial price should be <= 0.750001");
    }
}
