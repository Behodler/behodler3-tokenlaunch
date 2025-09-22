// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockBondingToken.sol";
import "@vault/mocks/MockERC20.sol";
import "@vault/mocks/MockVault.sol";

/**
 * @title VirtualLiquidityTest
 * @notice Comprehensive tests for virtual liquidity constant offset bonding curve implementation
 * @dev Tests core relationships, edge cases, and mathematical accuracy
 */
contract VirtualLiquidityTest is Test {
    Behodler3Tokenlaunch public b3;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;
    MockVault public vault;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    // Test constants for example parameters (zero seed enforcement)
    uint256 constant FUNDING_GOAL = 1_000_000 * 1e18; // 1M tokens
    uint256 constant SEED_INPUT = 0; // Always zero with zero seed enforcement
    uint256 constant DESIRED_AVG_PRICE = 0.9e18; // 0.9 (90% of final price) - must be >= sqrt(0.75)

    // Expected calculated values
    uint256 public expectedAlpha;
    uint256 public expectedVirtualK;
    uint256 public expectedInitialPrice;

    event VirtualLiquidityGoalsSet(
        uint256 fundingGoal,
        uint256 seedInput,
        uint256 desiredAveragePrice,
        uint256 alpha,
        uint256 beta,
        uint256 virtualK
    );

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        bondingToken = new MockBondingToken("BondingToken", "BOND");
        inputToken = new MockERC20("TestToken", "TEST", 18);
        vault = new MockVault(owner);

        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(inputToken, bondingToken, vault);

        // Setup vault authorization
        vault.setClient(address(b3), true);
        b3.initializeVaultApproval();

        // Calculate expected values for tests with zero seed
        // alpha = (P_ave * x_fin) / (1 - P_ave) when x_0 = 0
        uint256 numerator = (DESIRED_AVG_PRICE * FUNDING_GOAL) / 1e18;
        uint256 denominator = 1e18 - DESIRED_AVG_PRICE;
        expectedAlpha = (numerator * 1e18) / denominator;

        // k = (x_fin + alpha)^2
        uint256 xFinPlusAlpha = FUNDING_GOAL + expectedAlpha;
        expectedVirtualK = xFinPlusAlpha * xFinPlusAlpha;

        // P_0 = (P_ave)^2
        expectedInitialPrice = (DESIRED_AVG_PRICE * DESIRED_AVG_PRICE) / 1e18;

        vm.stopPrank();
    }

    /**
     * @notice Test setting goals calculates correct parameters
     */
    function test_SetGoals_CalculatesCorrectParameters() public {
        vm.prank(owner);

        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Verify stored parameters
        assertEq(b3.fundingGoal(), FUNDING_GOAL, "Funding goal should match");
        assertEq(b3.seedInput(), 0, "Seed input should always be zero");
        assertEq(b3.desiredAveragePrice(), DESIRED_AVG_PRICE, "Desired average price should match");

        // Get actual values from contract for verification
        uint256 actualAlpha = b3.alpha();
        uint256 actualBeta = b3.beta();
        uint256 actualVirtualK = b3.virtualK();

        assertEq(actualBeta, actualAlpha, "Beta should equal alpha");
        assertTrue(b3.isVirtualPairInitialized(), "Virtual liquidity should be initialized");

        // Verify alpha calculation for zero seed: alpha = (P_ave * x_fin) / (1 - P_ave)
        uint256 numerator = (DESIRED_AVG_PRICE * FUNDING_GOAL) / 1e18;
        uint256 denominator = 1e18 - DESIRED_AVG_PRICE;
        uint256 expectedAlphaCalculated = (numerator * 1e18) / denominator;
        assertEq(actualAlpha, expectedAlphaCalculated, "Alpha should be calculated correctly");

        // Verify K calculation: k = (x_fin + alpha)^2
        uint256 xFinPlusAlpha = FUNDING_GOAL + actualAlpha;
        uint256 expectedVirtualKCalculated = xFinPlusAlpha * xFinPlusAlpha;
        assertEq(actualVirtualK, expectedVirtualKCalculated, "Virtual K should be calculated correctly");
    }

    /**
     * @notice Test setGoals input validation
     */
    function test_SetGoals_InputValidation() public {
        vm.startPrank(owner);

        // Test funding goal must be positive
        vm.expectRevert("VL: Funding goal must be positive");
        b3.setGoals(0, DESIRED_AVG_PRICE);

        // Test desired average price must be >= sqrt(0.75) for P0 >= 0.75
        vm.expectRevert("VL: Average price must be >= sqrt(0.75) for P0 >= 0.75");
        b3.setGoals(FUNDING_GOAL, 0.8e18); // Below sqrt(0.75)

        // Test desired average price must be < 1
        vm.expectRevert("VL: Average price must be < 1");
        b3.setGoals(FUNDING_GOAL, 1.5e18);

        vm.expectRevert("VL: Average price must be < 1");
        b3.setGoals(FUNDING_GOAL, 1e18);

        vm.stopPrank();
    }

    /**
     * @notice Test initial marginal price calculation P_0 = (P_ave)^2
     */
    function test_InitialMarginalPrice_EqualsSquareOfAveragePrice() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        uint256 initialPrice = b3.getInitialMarginalPrice();
        assertEq(initialPrice, expectedInitialPrice, "Initial price should equal P_ave squared");

        // Verify it equals 0.81e18 for 0.9e18 average price
        assertEq(initialPrice, 0.81e18, "Initial price should be 0.81 for 0.9 average price");
    }

    /**
     * @notice Test current marginal price starts at initial price
     */
    function test_CurrentMarginalPrice_StartsAtInitialPrice() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        uint256 currentPrice = b3.getCurrentMarginalPrice();
        uint256 initialPrice = b3.getInitialMarginalPrice();

        // Allow for small rounding differences
        uint256 tolerance = 1e15; // 0.001
        assertApproxEqAbs(currentPrice, initialPrice, tolerance, "Current price should start at initial price");
    }

    /**
     * @notice Test final marginal price is 1.0
     */
    function test_FinalMarginalPrice_IsOne() public {
        uint256 finalPrice = b3.getFinalMarginalPrice();
        assertEq(finalPrice, 1e18, "Final price should be 1.0");
    }

    /**
     * @notice Test virtual liquidity is always enabled (no toggle)
     */
    function test_VirtualLiquidityAlwaysEnabled() public {
        // Virtual liquidity is always enabled after setGoals
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        assertTrue(b3.isVirtualPairInitialized(), "Virtual liquidity should be initialized");
        assertGt(b3.virtualK(), 0, "Virtual K should be positive");
        assertGt(b3.alpha(), 0, "Alpha should be positive");
        assertGt(b3.beta(), 0, "Beta should be positive");
    }

    /**
     * @notice Test virtual liquidity quote calculation returns reasonable values
     */
    function test_VirtualLiquidityQuote_ReturnsReasonableValues() public {
        vm.startPrank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);
        vm.stopPrank();

        uint256 inputAmount = 10_000 * 1e18;

        // Get virtual liquidity quote
        uint256 virtualQuote = b3.quoteAddLiquidity(inputAmount);

        // Quote should be positive and reasonable
        assertGt(virtualQuote, 0, "Quote should be positive");
        // Since initial price is less than 1, we can get more bonding tokens than input tokens
        assertGt(virtualQuote, inputAmount / 2, "Quote should be reasonably sized");
    }

    /**
     * @notice Test add liquidity with virtual liquidity enabled
     */
    function test_AddLiquidity_WithVirtualLiquidity() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Give user tokens
        uint256 inputAmount = 5000 * 1e18;
        deal(address(inputToken), user1, inputAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);

        uint256 bondingTokensBefore = bondingToken.balanceOf(user1);
        uint256 quotedTokens = b3.quoteAddLiquidity(inputAmount);

        uint256 actualTokens = b3.addLiquidity(inputAmount, 0);

        assertEq(actualTokens, quotedTokens, "Actual tokens should match quote");
        assertEq(
            bondingToken.balanceOf(user1), bondingTokensBefore + actualTokens, "User should receive bonding tokens"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test remove liquidity with virtual liquidity enabled
     */
    function test_RemoveLiquidity_WithVirtualLiquidity() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Give user tokens and add liquidity first
        uint256 inputAmount = 5000 * 1e18;
        deal(address(inputToken), user1, inputAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        uint256 bondingTokens = b3.addLiquidity(inputAmount, 0);

        // Now test removing liquidity
        uint256 inputTokensBefore = inputToken.balanceOf(user1);
        uint256 quotedInput = b3.quoteRemoveLiquidity(bondingTokens);

        uint256 actualInput = b3.removeLiquidity(bondingTokens, 0);

        assertEq(actualInput, quotedInput, "Actual input should match quote");
        assertEq(inputToken.balanceOf(user1), inputTokensBefore + actualInput, "User should receive input tokens");
        assertEq(bondingToken.balanceOf(user1), 0, "User should have no bonding tokens left");

        vm.stopPrank();
    }

    /**
     * @notice Test price bounds are enforced during operations
     */
    function test_PriceBounds_AreEnforced() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Price should be within bounds initially
        uint256 currentPrice = b3.getCurrentMarginalPrice();
        uint256 initialPrice = b3.getInitialMarginalPrice();
        uint256 finalPrice = b3.getFinalMarginalPrice();

        assertGe(currentPrice, initialPrice, "Current price should be >= initial price");
        assertLe(currentPrice, finalPrice, "Current price should be <= final price");
    }

    /**
     * @notice Test total raised calculation
     */
    function test_TotalRaised_CalculatedCorrectly() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Initially should be 0
        assertEq(b3.getTotalRaised(), 0, "Initially no tokens raised");

        // Add some liquidity
        uint256 inputAmount = 5000 * 1e18;
        deal(address(inputToken), user1, inputAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();

        // Should now show tokens raised
        uint256 totalRaised = b3.getTotalRaised();
        assertGt(totalRaised, 0, "Should have raised some tokens");
        assertLe(totalRaised, inputAmount, "Raised amount should not exceed input");
    }

    /**
     * @notice Test average price calculation
     */
    function test_AveragePrice_CalculatedCorrectly() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Initially should be 0 (no tokens issued)
        assertEq(b3.getAveragePrice(), 0, "Initially no average price");

        // Add some liquidity
        uint256 inputAmount = 5000 * 1e18;
        deal(address(inputToken), user1, inputAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();

        // Should now have an average price
        uint256 avgPrice = b3.getAveragePrice();
        assertGt(avgPrice, 0, "Should have positive average price");
    }

    /**
     * @notice Test that holders cannot claim more than available liquidity
     */
    function test_HoldersCannot_ClaimMoreThanAvailable() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Add some liquidity
        uint256 inputAmount = 5000 * 1e18;
        deal(address(inputToken), user1, inputAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        uint256 bondingTokens = b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();

        // Try to remove more liquidity than added (should fail due to balance check)
        vm.startPrank(user1);
        vm.expectRevert("B3: Insufficient bonding tokens");
        b3.removeLiquidity(bondingTokens + 1, 0);
        vm.stopPrank();
    }

    /**
     * @notice Test with exact example parameters from story
     */
    function test_ExampleParameters_XFin1M_X01K_PAve09() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Verify initial marginal price is 0.81
        uint256 initialPrice = b3.getInitialMarginalPrice();
        assertEq(initialPrice, 0.81e18, "Initial price should be 0.81");

        // Verify final marginal price is 1.0
        uint256 finalPrice = b3.getFinalMarginalPrice();
        assertEq(finalPrice, 1e18, "Final price should be 1.0");

        // Verify goals are stored correctly
        assertEq(b3.fundingGoal(), FUNDING_GOAL, "Funding goal should be 1M");
        assertEq(b3.seedInput(), 0, "Seed input should always be 0");
        assertEq(b3.desiredAveragePrice(), DESIRED_AVG_PRICE, "Average price should be 0.9");
    }

    /**
     * @notice Test mathematical invariant (x+alpha)(y+beta)=k holds
     */
    function test_MathematicalInvariant_Holds() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Get initial state
        (uint256 virtualInputTokens, uint256 virtualL,) = b3.getVirtualPair();
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 virtualK = b3.virtualK();

        // Check initial invariant
        uint256 leftSide = (virtualInputTokens + alpha) * (virtualL + beta);
        assertApproxEqRel(leftSide, virtualK, 1e15, "Initial invariant should hold"); // 0.1% tolerance

        // Add liquidity and check invariant still holds
        uint256 inputAmount = 1000 * 1e18;
        deal(address(inputToken), user1, inputAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), inputAmount);
        b3.addLiquidity(inputAmount, 0);
        vm.stopPrank();

        // Check invariant after operation
        (virtualInputTokens, virtualL,) = b3.getVirtualPair();
        leftSide = (virtualInputTokens + alpha) * (virtualL + beta);
        assertApproxEqRel(leftSide, virtualK, 1e15, "Invariant should hold after add liquidity"); // 0.1% tolerance
    }

    /**
     * @notice Test edge case: very small amounts
     */
    function test_EdgeCase_VerySmallAmounts() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        uint256 smallAmount = 1e18; // 1 token
        deal(address(inputToken), user1, smallAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), smallAmount);

        // Should not revert
        uint256 bondingTokens = b3.addLiquidity(smallAmount, 0);
        assertGt(bondingTokens, 0, "Should receive some bonding tokens");

        vm.stopPrank();
    }

    /**
     * @notice Test edge case: approaching funding goal
     */
    function test_EdgeCase_ApproachingFundingGoal() public {
        vm.prank(owner);
        b3.setGoals(1000e18, 0.9e18); // Smaller numbers for testing

        // Add liquidity close to funding goal
        uint256 largeAmount = 850e18; // Close to goal
        deal(address(inputToken), user1, largeAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), largeAmount);

        // Should not revert and price should remain bounded
        b3.addLiquidity(largeAmount, 0);

        uint256 currentPrice = b3.getCurrentMarginalPrice();
        uint256 finalPrice = b3.getFinalMarginalPrice();

        assertLe(currentPrice, finalPrice, "Price should not exceed final price");

        vm.stopPrank();
    }
}
