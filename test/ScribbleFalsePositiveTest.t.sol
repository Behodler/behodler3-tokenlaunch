// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ScribbleValidationContract.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockBondingToken.sol";
import "@vault/mocks/MockVault.sol";

/**
 * @title ScribbleFalsePositiveTest
 * @notice Test suite to verify that Scribble specifications don't create false positives
 * @dev These tests ensure that valid operations pass without triggering specification violations
 */
contract ScribbleFalsePositiveTest is Test {
    ScribbleValidationContract public validationContract;
    Behodler3Tokenlaunch public tokenLaunch;
    MockERC20 public inputToken;
    MockBondingToken public bondingToken;
    MockVault public vault;

    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    function setUp() public {
        validationContract = new ScribbleValidationContract();

        // Set up TokenLaunch test environment
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));

        tokenLaunch = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IYieldStrategy(address(vault))
        );

        // Initialize vault approval
        vault.setClient(address(tokenLaunch), true);
        tokenLaunch.initializeVaultApproval();

        // Set up initial goals for tokenLaunch
        tokenLaunch.setGoals(1000 ether, 9e17); // 90% desired average price, above sqrt(0.75)

        // Mint tokens for testing
        inputToken.mint(address(this), 10_000 ether);
        inputToken.mint(user1, 5000 ether);
        inputToken.mint(user2, 5000 ether);
        inputToken.mint(user3, 5000 ether);

        // Approve spending
        inputToken.approve(address(tokenLaunch), 10_000 ether);
        vm.prank(user1);
        inputToken.approve(address(tokenLaunch), 5000 ether);
        vm.prank(user2);
        inputToken.approve(address(tokenLaunch), 5000 ether);
        vm.prank(user3);
        inputToken.approve(address(tokenLaunch), 5000 ether);
    }

    /**
     * @notice Test that normal deposit operations don't trigger false positives
     */
    function testNormalDepositOperationsValid() public {
        // Single deposit should pass all specifications
        validationContract.deposit(100);

        // Multiple deposits should pass
        validationContract.deposit(50);
        validationContract.deposit(200);
        validationContract.deposit(75);

        // Verify final state is correct
        assertEq(validationContract.balance(), 425);
        assertEq(validationContract.totalDeposits(), 425);
        assertEq(validationContract.getUserDeposit(address(this)), 425);
    }

    /**
     * @notice Test that normal withdraw operations don't trigger false positives
     */
    function testNormalWithdrawOperationsValid() public {
        // Deposit first
        validationContract.deposit(500);

        // Partial withdrawals should pass
        validationContract.withdraw(100);
        validationContract.withdraw(50);
        validationContract.withdraw(150);

        // Full withdrawal of remaining balance
        validationContract.withdraw(200);

        // Verify final state
        assertEq(validationContract.balance(), 0);
        assertEq(validationContract.totalDeposits(), 500); // Total deposits should remain
        assertEq(validationContract.getUserDeposit(address(this)), 0);
    }

    /**
     * @notice Test that multi-user operations don't trigger false positives
     */
    function testMultiUserOperationsValid() public {
        // User 1 deposits
        vm.prank(user1);
        validationContract.deposit(1000);

        // User 2 deposits
        vm.prank(user2);
        validationContract.deposit(2000);

        // User 3 deposits
        vm.prank(user3);
        validationContract.deposit(1500);

        // Verify global state
        assertEq(validationContract.balance(), 4500);
        assertEq(validationContract.totalDeposits(), 4500);

        // User 1 partial withdraw
        vm.prank(user1);
        validationContract.withdraw(500);

        // User 2 full withdraw
        vm.prank(user2);
        validationContract.withdraw(2000);

        // Verify state after withdrawals
        assertEq(validationContract.balance(), 2000); // 4500 - 500 - 2000
        assertEq(validationContract.totalDeposits(), 4500); // Unchanged
        assertEq(validationContract.getUserDeposit(user1), 500);
        assertEq(validationContract.getUserDeposit(user2), 0);
        assertEq(validationContract.getUserDeposit(user3), 1500);
    }

    /**
     * @notice Test that TokenLaunch goal setting doesn't trigger false positives
     */
    function testTokenLaunchGoalSettingValid() public {
        // Test various valid goal configurations
        tokenLaunch.setGoals(2000 ether, 9e17); // 90% desired average price, above sqrt(0.75)

        // Verify state is consistent
        assertTrue(tokenLaunch.fundingGoal() > tokenLaunch.seedInput());
        assertTrue(tokenLaunch.desiredAveragePrice() > 0);
        assertTrue(tokenLaunch.desiredAveragePrice() < 1e18);
        assertTrue(tokenLaunch.virtualK() > 0);
        assertTrue(tokenLaunch.alpha() > 0);
        assertTrue(tokenLaunch.beta() > 0);

        // Another valid configuration
        tokenLaunch.setGoals(5000 ether, 9e17); // 90% desired average price, above sqrt(0.75)

        // Verify consistency again
        assertTrue(tokenLaunch.fundingGoal() > tokenLaunch.seedInput());
        assertTrue(tokenLaunch.desiredAveragePrice() > 0);
        assertTrue(tokenLaunch.desiredAveragePrice() < 1e18);
    }

    /**
     * @notice Test that TokenLaunch liquidity operations don't trigger false positives
     */
    function testTokenLaunchLiquidityOperationsValid() public {
        // Add liquidity operations should pass specifications
        uint256 balanceBefore = bondingToken.balanceOf(address(this));

        tokenLaunch.addLiquidity(200 ether, 0);

        uint256 balanceAfter = bondingToken.balanceOf(address(this));
        assertTrue(balanceAfter > balanceBefore, "Bonding tokens should be minted");

        // Multiple add liquidity operations
        tokenLaunch.addLiquidity(100 ether, 0);
        tokenLaunch.addLiquidity(150 ether, 0);

        // Remove some liquidity
        uint256 bondingTokenBalance = bondingToken.balanceOf(address(this));
        bondingToken.approve(address(tokenLaunch), bondingTokenBalance);

        tokenLaunch.removeLiquidity(bondingTokenBalance / 4, 0); // Remove 25%

        // Verify state remains consistent
        assertTrue(tokenLaunch.virtualK() > 0);
        assertTrue(tokenLaunch.virtualInputTokens() >= tokenLaunch.seedInput());
    }

    /**
     * @notice Test that view function calls don't trigger false positives
     */
    function testViewFunctionCallsValid() public {
        // Price queries should not trigger any specifications
        uint256 marginalPrice = tokenLaunch.getCurrentMarginalPrice();
        assertTrue(marginalPrice > 0, "Marginal price should be positive");

        uint256 averagePrice = tokenLaunch.getAveragePrice();
        // Average price can be 0 initially, that's valid

        uint256 totalRaised = tokenLaunch.getTotalRaised();
        assertTrue(totalRaised >= 0, "Total raised should be non-negative");

        // State queries
        uint256 virtualK = tokenLaunch.virtualK();
        uint256 virtualL = tokenLaunch.virtualL();
        uint256 virtualInputTokens = tokenLaunch.virtualInputTokens();
        uint256 alpha = tokenLaunch.alpha();
        uint256 beta = tokenLaunch.beta();

        // These should all be consistent without triggering false positives
        assertTrue(virtualK > 0);
        assertTrue(virtualL > 0);
        // With zero seed enforcement, virtualInputTokens starts at 0 (x₀ = 0)
        assertEq(virtualInputTokens, 0, "Virtual input should be 0 initially with zero seed");
        assertTrue(alpha > 0);
        assertTrue(beta > 0);
    }

    /**
     * @notice Test that contract state transitions don't trigger false positives
     */
    function testStateTransitionsValid() public {
        // Lock and unlock operations should be valid
        assertFalse(tokenLaunch.locked());

        tokenLaunch.lock();
        assertTrue(tokenLaunch.locked());

        tokenLaunch.unlock();
        assertFalse(tokenLaunch.locked());

        // Vault approval state changes
        assertTrue(tokenLaunch.vaultApprovalInitialized());

        // These state changes should not trigger specification violations
    }

    /**
     * @notice Test that mathematical operations maintain specification validity
     */
    function testMathematicalOperationsValid() public {
        // Perform operations that involve complex calculations
        tokenLaunch.addLiquidity(123 ether, 0); // Non-round number

        uint256 marginalPriceBefore = tokenLaunch.getCurrentMarginalPrice();

        tokenLaunch.addLiquidity(456 ether, 0); // Another non-round number

        uint256 marginalPriceAfter = tokenLaunch.getCurrentMarginalPrice();

        // Price should increase as more liquidity is added (curve property)
        assertTrue(marginalPriceAfter > marginalPriceBefore, "Marginal price should increase");

        // Remove some liquidity
        uint256 bondingTokens = bondingToken.balanceOf(address(this));
        bondingToken.approve(address(tokenLaunch), bondingTokens);

        tokenLaunch.removeLiquidity(bondingTokens / 3, 0);

        // All mathematical operations should maintain specification validity
        assertTrue(tokenLaunch.virtualK() > 0);
    }

    /**
     * @notice Test that boundary value operations don't trigger false positives
     */
    function testBoundaryValueOperationsValid() public {
        // Test with minimum valid values
        validationContract.deposit(1); // Minimum deposit

        // Test with reasonable maximum values
        validationContract.deposit(1_000_000 ether);

        // Withdraw operations at boundaries
        validationContract.withdraw(1); // Minimum withdraw
        validationContract.withdraw(1_000_000 ether); // Large withdraw

        // All boundary operations should pass specifications
    }

    /**
     * @notice Test that repeated operations don't accumulate false positives
     */
    function testRepeatedOperationsValid() public {
        // Perform many repeated operations
        for (uint256 i = 1; i <= 20; i++) {
            validationContract.deposit(i * 10);
        }

        // Verify invariants still hold after many operations
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
        assertTrue(validationContract.balance() > 0);

        // Perform many withdrawals
        for (uint256 i = 1; i <= 10; i++) {
            validationContract.withdraw(i * 10);
        }

        // Invariants should still hold
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
    }

    /**
     * @notice Test that complex interaction patterns don't trigger false positives
     */
    function testComplexInteractionPatternsValid() public {
        // Pattern 1: Interleaved deposits and withdrawals
        validationContract.deposit(100);
        validationContract.withdraw(50);
        validationContract.deposit(200);
        validationContract.withdraw(75);
        validationContract.deposit(300);

        // Pattern 2: Multiple users with complex interactions
        vm.prank(user1);
        validationContract.deposit(500);

        vm.prank(user2);
        validationContract.deposit(750);

        vm.prank(user1);
        validationContract.withdraw(250);

        vm.prank(user3);
        validationContract.deposit(1000);

        vm.prank(user2);
        validationContract.withdraw(375);

        // All these complex patterns should maintain specification validity
        assertTrue(validationContract.balance() <= validationContract.totalDeposits());
        assertTrue(validationContract.balance() >= 0);
        assertTrue(validationContract.totalDeposits() >= 0);
    }

    /**
     * @notice Test that TokenLaunch pricing functions don't trigger false positives
     */
    function testTokenLaunchPricingFunctionsValid() public {
        // Add some liquidity to create a meaningful price
        tokenLaunch.addLiquidity(500 ether, 0);

        // Quote functions should work without triggering specifications
        uint256 bondingTokensOut = tokenLaunch.quoteAddLiquidity(100 ether);
        assertTrue(bondingTokensOut > 0, "Quote should return positive bonding tokens");

        uint256 inputTokensOut = tokenLaunch.quoteRemoveLiquidity(bondingTokensOut);
        assertTrue(inputTokensOut > 0, "Quote should return positive input tokens");

        // These pricing operations should not trigger any false positives
        uint256 currentPrice = tokenLaunch.getCurrentMarginalPrice();
        uint256 averagePrice = tokenLaunch.getAveragePrice();

        assertTrue(currentPrice > 0, "Current price should be positive");
        assertTrue(averagePrice > 0, "Average price should be positive after liquidity addition");
    }

    /**
     * @notice Test that specification checking itself doesn't interfere with normal operations
     */
    function testSpecificationOverheadValid() public {
        uint256 gasBefore = gasleft();

        // Perform operations and measure gas impact of specifications
        validationContract.deposit(1000);
        validationContract.withdraw(500);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Gas usage should be reasonable (specifications shouldn't add excessive overhead)
        assertTrue(gasUsed < 1_000_000, "Specification overhead should be reasonable");

        // Operations should still complete successfully
        assertEq(validationContract.balance(), 500);
        assertEq(validationContract.getUserDeposit(address(this)), 500);
    }
}
