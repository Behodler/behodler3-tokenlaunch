// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockBondingToken.sol";
import "@vault/mocks/MockERC20.sol";
import "@vault/mocks/MockVault.sol";

/**
 * @title ZeroSeedVirtualLiquidityTest
 * @notice Comprehensive testing for zero seed virtual liquidity scenarios
 * @dev Focuses on mathematical properties, edge cases, and zero seed enforcement from story 031.2
 */
contract ZeroSeedVirtualLiquidityTest is Test {
    Behodler3Tokenlaunch public b3;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;
    MockVault public vault;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    // Test scenarios with various P_avg values
    uint256 constant FUNDING_GOAL = 1_000_000 * 1e18; // 1M tokens

    // P_avg test values - all must be >= sqrt(0.75) approximately 0.866025403784438647
    uint256 constant MIN_P_AVG = 866025403784438647; // Exactly sqrt(0.75)
    uint256 constant LOW_P_AVG = 0.88e18; // Slightly above minimum
    uint256 constant MID_P_AVG = 0.9e18; // Middle value
    uint256 constant HIGH_P_AVG = 0.95e18; // High value
    uint256 constant VERY_HIGH_P_AVG = 0.98e18; // Very high value
    uint256 constant MAX_P_AVG = 0.985e18; // Just below 0.99 to avoid overflow

    // Gas cost tracking
    uint256 constant MAX_ACCEPTABLE_GAS = 250000; // 250k gas limit for operations

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

        vm.stopPrank();
    }

    /**
     * @notice Test zero seed enforcement across all scenarios
     */
    function test_ZeroSeedEnforcement_AllScenarios() public {
        uint256[6] memory testPrices = [MIN_P_AVG, LOW_P_AVG, MID_P_AVG, HIGH_P_AVG, VERY_HIGH_P_AVG, MAX_P_AVG];

        for (uint256 i = 0; i < testPrices.length; i++) {
            vm.prank(owner);
            b3.setGoals(FUNDING_GOAL, testPrices[i]);

            // Verify seed input is always zero
            assertEq(b3.seedInput(), 0, "Seed input must always be zero");

            // Verify virtual input tokens start at zero
            (uint256 virtualInputTokens,,) = b3.getVirtualPair();
            assertEq(virtualInputTokens, 0, "Virtual input tokens must start at zero");

            // Verify total raised starts at zero
            assertEq(b3.getTotalRaised(), 0, "Total raised must start at zero with zero seed");
        }
    }

    /**
     * @notice Test comprehensive scenarios with various P_avg values
     */
    function test_ZeroSeed_VariousPAvgValues() public {
        uint256[6] memory testPrices = [MIN_P_AVG, LOW_P_AVG, MID_P_AVG, HIGH_P_AVG, VERY_HIGH_P_AVG, MAX_P_AVG];

        for (uint256 i = 0; i < testPrices.length; i++) {
            uint256 pAvg = testPrices[i];

            vm.prank(owner);
            b3.setGoals(FUNDING_GOAL, pAvg);

            // Test mathematical properties
            _testZeroSeedMathematicalProperties(pAvg);

            // Test price progression
            _testPriceProgression(pAvg);

            // Test invariant preservation
            _testInvariantPreservation(pAvg);
        }
    }

    /**
     * @notice Test that curvature remains near-linear (max deviation < 1% from linear)
     */
    function test_CurvatureNearLinear_MaxDeviation1Percent() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, MID_P_AVG);

        uint256 numSamples = 20; // Test 20 points along the curve
        uint256 maxDeviation = 0;

        for (uint256 i = 1; i <= numSamples; i++) {
            uint256 inputAmount = (FUNDING_GOAL * i) / (numSamples + 1); // Avoid reaching exact funding goal

            // Calculate expected linear price progression
            // Linear would be: price = initialPrice + (finalPrice - initialPrice) * progress
            uint256 progress = (inputAmount * 1e18) / FUNDING_GOAL;
            uint256 initialPrice = b3.getInitialMarginalPrice();
            uint256 finalPrice = b3.getFinalMarginalPrice();
            uint256 expectedLinearPrice = initialPrice + ((finalPrice - initialPrice) * progress) / 1e18;

            // Get actual price by simulating the purchase
            vm.startPrank(user1);
            deal(address(inputToken), user1, inputAmount);
            inputToken.approve(address(b3), inputAmount);
            b3.addLiquidity(inputAmount, 0);
            vm.stopPrank();

            uint256 actualPrice = b3.getCurrentMarginalPrice();

            // Calculate deviation percentage
            uint256 deviation;
            if (actualPrice > expectedLinearPrice) {
                deviation = ((actualPrice - expectedLinearPrice) * 10000) / expectedLinearPrice; // Basis points
            } else {
                deviation = ((expectedLinearPrice - actualPrice) * 10000) / expectedLinearPrice; // Basis points
            }

            if (deviation > maxDeviation) {
                maxDeviation = deviation;
            }

            // Reset state for next iteration
            vm.prank(owner);
            b3.setGoals(FUNDING_GOAL, MID_P_AVG);
        }

        // Assert maximum deviation is less than 1% (100 basis points)
        assertLt(maxDeviation, 100, "Curvature deviation must be less than 1%");
    }

    /**
     * @notice Test fair price progression across entire purchase timeline
     */
    function test_FairPriceProgression_EntireTimeline() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, MID_P_AVG);

        uint256 initialPrice = b3.getInitialMarginalPrice();
        uint256 finalPrice = b3.getFinalMarginalPrice();
        uint256 previousPrice = initialPrice;

        // Test price progression through 10 steps
        for (uint256 i = 1; i <= 10; i++) {
            uint256 stepAmount = FUNDING_GOAL / 20; // 5% of funding goal per step

            deal(address(inputToken), user1, stepAmount);
            vm.startPrank(user1);
            inputToken.approve(address(b3), stepAmount);
            b3.addLiquidity(stepAmount, 0);
            vm.stopPrank();

            uint256 currentPrice = b3.getCurrentMarginalPrice();

            // Verify price is monotonically increasing
            assertGe(currentPrice, previousPrice, "Price must be monotonically increasing");

            // Verify price is within bounds
            assertGe(currentPrice, initialPrice, "Price must be >= initial price");
            assertLe(currentPrice, finalPrice, "Price must be <= final price");

            // Verify reasonable price progression (no sudden jumps)
            if (i > 1) {
                uint256 priceIncrease = currentPrice - previousPrice;
                uint256 maxReasonableIncrease = (finalPrice - initialPrice) / 5; // Max 20% of total range per step
                assertLe(priceIncrease, maxReasonableIncrease, "Price increase must be reasonable");
            }

            previousPrice = currentPrice;
        }

        // Verify final price approaches but doesn't exceed 1.0
        assertLe(previousPrice, finalPrice, "Final achieved price must not exceed theoretical final price");
    }

    /**
     * @notice Test edge cases with very high P_avg values and boundary conditions
     */
    function test_EdgeCases_HighPAvgAndBoundaries() public {
        // Test minimum valid P_avg (exactly sqrt(0.75))
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, MIN_P_AVG);

        uint256 initialPrice = b3.getInitialMarginalPrice();
        assertEq(initialPrice, 750000000000000000, "Initial price should be exactly 0.75 for min P_avg");

        // Test very high P_avg (0.98)
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, VERY_HIGH_P_AVG);

        initialPrice = b3.getInitialMarginalPrice();
        uint256 expectedInitialPrice = (VERY_HIGH_P_AVG * VERY_HIGH_P_AVG) / 1e18;
        assertEq(initialPrice, expectedInitialPrice, "Initial price should be P_avg squared");

        // Test operations with very high P_avg work correctly
        uint256 testAmount = 1000 * 1e18;
        deal(address(inputToken), user1, testAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), testAmount);
        uint256 bondingTokens = b3.addLiquidity(testAmount, 0);
        vm.stopPrank();

        assertGt(bondingTokens, 0, "Should receive bonding tokens even with very high P_avg");

        // Test maximum valid P_avg (0.985)
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, MAX_P_AVG);

        initialPrice = b3.getInitialMarginalPrice();
        assertLt(initialPrice, 1e18, "Initial price should be less than 1.0");

        // Test small funding goal edge case
        uint256 smallFundingGoal = 1000 * 1e18;
        vm.prank(owner);
        b3.setGoals(smallFundingGoal, MID_P_AVG);

        assertTrue(b3.isVirtualPairInitialized(), "Should initialize with small funding goal");

        // Test large funding goal edge case (reduced to avoid overflow)
        uint256 largeFundingGoal = 100_000_000 * 1e18; // 100M tokens
        vm.prank(owner);
        b3.setGoals(largeFundingGoal, LOW_P_AVG); // Use lower P_avg to avoid overflow

        assertTrue(b3.isVirtualPairInitialized(), "Should initialize with large funding goal");
    }

    /**
     * @notice Test that gas costs remain reasonable for zero seed operations
     */
    function test_GasCosts_RemainReasonable() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, MID_P_AVG);

        uint256 testAmount = 1000 * 1e18;
        deal(address(inputToken), user1, testAmount * 10);

        vm.startPrank(user1);
        inputToken.approve(address(b3), testAmount * 10);

        // Test addLiquidity gas cost
        uint256 gasBefore = gasleft();
        b3.addLiquidity(testAmount, 0);
        uint256 addLiquidityGas = gasBefore - gasleft();

        assertLt(addLiquidityGas, MAX_ACCEPTABLE_GAS, "AddLiquidity gas cost must be reasonable");

        // Test removeLiquidity gas cost
        uint256 bondingTokenBalance = bondingToken.balanceOf(user1);
        gasBefore = gasleft();
        b3.removeLiquidity(bondingTokenBalance / 2, 0);
        uint256 removeLiquidityGas = gasBefore - gasleft();

        assertLt(removeLiquidityGas, MAX_ACCEPTABLE_GAS, "RemoveLiquidity gas cost must be reasonable");

        // Test quote functions gas cost
        gasBefore = gasleft();
        b3.quoteAddLiquidity(testAmount);
        uint256 quoteAddGas = gasBefore - gasleft();

        gasBefore = gasleft();
        b3.quoteRemoveLiquidity(bondingTokenBalance / 2);
        uint256 quoteRemoveGas = gasBefore - gasleft();

        assertLt(quoteAddGas, 50000, "Quote add liquidity gas cost must be very low");
        assertLt(quoteRemoveGas, 50000, "Quote remove liquidity gas cost must be very low");

        vm.stopPrank();
    }

    /**
     * @notice Test mathematical properties for zero seed scenarios
     */
    function _testZeroSeedMathematicalProperties(uint256 pAvg) internal {
        // Test P_0 = P_avg² formula
        uint256 initialPrice = b3.getInitialMarginalPrice();
        uint256 expectedInitialPrice = (pAvg * pAvg) / 1e18;
        assertEq(initialPrice, expectedInitialPrice, "P_0 should equal P_avg squared");

        // Test alpha = (P_avg * x_fin) / (1 - P_avg) formula
        uint256 alpha = b3.alpha();
        uint256 numerator = (pAvg * FUNDING_GOAL) / 1e18;
        uint256 denominator = 1e18 - pAvg;
        uint256 expectedAlpha = (numerator * 1e18) / denominator;
        assertEq(alpha, expectedAlpha, "Alpha should be calculated correctly for zero seed");

        // Test beta = alpha
        uint256 beta = b3.beta();
        assertEq(beta, alpha, "Beta should equal alpha");

        // Test k = (x_fin + alpha)^2
        uint256 virtualK = b3.virtualK();
        uint256 xFinPlusAlpha = FUNDING_GOAL + alpha;
        uint256 expectedVirtualK = xFinPlusAlpha * xFinPlusAlpha;
        assertEq(virtualK, expectedVirtualK, "Virtual K should be calculated correctly");

        // Test virtual liquidity: y_0 = k/alpha - alpha
        (uint256 virtualInputTokens, uint256 virtualL,) = b3.getVirtualPair();
        assertEq(virtualInputTokens, 0, "Virtual input tokens should start at zero");
        uint256 expectedVirtualL = virtualK / alpha - alpha;
        assertEq(virtualL, expectedVirtualL, "Virtual L should be calculated correctly");
    }

    /**
     * @notice Test price progression properties
     */
    function _testPriceProgression(uint256 pAvg) internal {
        uint256 testAmount = FUNDING_GOAL / 10; // 10% of funding goal
        deal(address(inputToken), user1, testAmount);

        uint256 initialPrice = b3.getCurrentMarginalPrice();

        vm.startPrank(user1);
        inputToken.approve(address(b3), testAmount);
        b3.addLiquidity(testAmount, 0);
        vm.stopPrank();

        uint256 newPrice = b3.getCurrentMarginalPrice();

        // Price should increase after adding liquidity
        assertGt(newPrice, initialPrice, "Price should increase after adding liquidity");

        // Price should still be bounded
        assertLe(newPrice, 1e18, "Price should not exceed 1.0");

        // Average price calculation should be reasonable
        uint256 avgPrice = b3.getAveragePrice();
        assertGt(avgPrice, 0, "Average price should be positive");
        assertLe(avgPrice, newPrice, "Average price should not exceed current marginal price");
    }

    /**
     * @notice Test invariant preservation
     */
    function _testInvariantPreservation(uint256 pAvg) internal {
        (uint256 virtualInputTokens, uint256 virtualL,) = b3.getVirtualPair();
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 virtualK = b3.virtualK();

        // Check (x+alpha)(y+beta)=k invariant with strict precision
        uint256 leftSide = (virtualInputTokens + alpha) * (virtualL + beta);
        // K invariant must be preserved with strict tolerance for mathematical correctness
        // Using relative tolerance of 0.0001% (1000x stricter than original 0.1%)
        uint256 tolerance = virtualK / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(leftSide, virtualK, tolerance, "Virtual liquidity invariant should hold within 0.0001% precision");

        // Add liquidity and check invariant still holds
        uint256 testAmount = FUNDING_GOAL / 20;
        deal(address(inputToken), user1, testAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), testAmount);
        b3.addLiquidity(testAmount, 0);
        vm.stopPrank();

        (virtualInputTokens, virtualL,) = b3.getVirtualPair();
        leftSide = (virtualInputTokens + alpha) * (virtualL + beta);
        // K invariant must be preserved with strict tolerance for mathematical correctness
        tolerance = virtualK / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(leftSide, virtualK, tolerance, "Virtual liquidity invariant should hold after operation within 0.0001% precision");
    }

    /**
     * @notice Test zero seed enforcement prevents any non-zero seed input
     */
    function test_ZeroSeedEnforcement_PreventsSeedInput() public {
        // The setGoals function enforces zero seed - no way to set non-zero seed
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, MID_P_AVG);

        // Verify seed is always zero regardless of any attempts to modify
        assertEq(b3.seedInput(), 0, "Seed input is immutably zero");

        // Test that virtual input tokens start at zero
        (uint256 virtualInputTokens,,) = b3.getVirtualPair();
        assertEq(virtualInputTokens, 0, "Virtual input tokens must start at zero");

        // Test that total raised starts at zero
        assertEq(b3.getTotalRaised(), 0, "Total raised must start at zero");
    }

    /**
     * @notice Test boundary condition: P_avg exactly at minimum threshold
     */
    function test_BoundaryCondition_MinimumPAvg() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, MIN_P_AVG); // Exactly sqrt(0.75)

        // Should succeed and create valid parameters
        assertTrue(b3.isVirtualPairInitialized(), "Should initialize with minimum P_avg");

        uint256 initialPrice = b3.getInitialMarginalPrice();
        assertEq(initialPrice, 750000000000000000, "Initial price should be exactly 0.75");

        // Test that operations work correctly
        uint256 testAmount = 1000 * 1e18;
        deal(address(inputToken), user1, testAmount);

        vm.startPrank(user1);
        inputToken.approve(address(b3), testAmount);
        uint256 bondingTokens = b3.addLiquidity(testAmount, 0);
        vm.stopPrank();

        assertGt(bondingTokens, 0, "Should receive bonding tokens at minimum P_avg");
    }

    /**
     * @notice Test invalid P_avg values are rejected
     */
    function test_InvalidPAvg_Rejected() public {
        vm.startPrank(owner);

        // Test P_avg below minimum threshold
        vm.expectRevert("VL: Average price must be >= sqrt(0.75) for P0 >= 0.75");
        b3.setGoals(FUNDING_GOAL, MIN_P_AVG - 1);

        // Test P_avg = 1.0 (should be rejected)
        vm.expectRevert("VL: Average price must be < 1");
        b3.setGoals(FUNDING_GOAL, 1e18);

        // Test P_avg > 1.0 (should be rejected)
        vm.expectRevert("VL: Average price must be < 1");
        b3.setGoals(FUNDING_GOAL, 1.1e18);

        vm.stopPrank();
    }

    /**
     * @notice Test price formula P(x) = (x+alpha)^2/k at various points
     */
    function test_PriceFormula_VariousPoints() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, MID_P_AVG);

        uint256 alpha = b3.alpha();
        uint256 virtualK = b3.virtualK();

        // Test at several points along the curve
        uint256[5] memory testInputs = [
            FUNDING_GOAL / 20, // 5%
            FUNDING_GOAL / 10, // 10%
            FUNDING_GOAL / 4, // 25%
            FUNDING_GOAL / 2, // 50%
            FUNDING_GOAL * 3 / 4 // 75%
        ];

        for (uint256 i = 0; i < testInputs.length; i++) {
            uint256 inputAmount = testInputs[i];

            // Calculate expected price using formula P(x) = (x+alpha)^2/k
            uint256 xPlusAlpha = inputAmount + alpha;
            uint256 expectedPrice = (xPlusAlpha * xPlusAlpha * 1e18) / virtualK;

            // Set up fresh state
            vm.prank(owner);
            b3.setGoals(FUNDING_GOAL, MID_P_AVG);

            // Add liquidity to reach the test point
            deal(address(inputToken), user1, inputAmount);
            vm.startPrank(user1);
            inputToken.approve(address(b3), inputAmount);
            b3.addLiquidity(inputAmount, 0);
            vm.stopPrank();

            uint256 actualPrice = b3.getCurrentMarginalPrice();

            // Allow for small rounding differences
            assertApproxEqRel(actualPrice, expectedPrice, 1e15, "Price should match formula P(x) = (x+alpha)^2/k");
        }
    }

    // ============================================
    // STORY 036.21: ZERO SEED MATHEMATICS TESTS
    // ============================================

    /**
     * @notice Test alpha calculation precision using formula: alpha = (P_avg * x_fin)/(1-P_avg)
     * @dev Validates the alpha calculation matches the architectural formula exactly
     * Reference: docs/zero-seed-virtual-liquidity-mathematics.md Section 2
     */
    function test_AlphaCalculationPrecision_FormulaValidation() public {
        // Test with multiple P_avg values to ensure formula consistency
        uint256[6] memory testPrices = [MIN_P_AVG, LOW_P_AVG, MID_P_AVG, HIGH_P_AVG, VERY_HIGH_P_AVG, MAX_P_AVG];

        for (uint256 i = 0; i < testPrices.length; i++) {
            uint256 pAvg = testPrices[i];

            vm.prank(owner);
            b3.setGoals(FUNDING_GOAL, pAvg);

            // Get actual alpha from contract
            uint256 actualAlpha = b3.alpha();

            // Calculate expected alpha using architecture formula: alpha = (P_avg * x_fin)/(1-P_avg)
            // Breaking down to avoid overflow and maintain precision:
            // numerator = P_avg * x_fin / 1e18 (scale down P_avg)
            // denominator = 1e18 - P_avg
            // expectedAlpha = (numerator * 1e18) / denominator (scale back up)
            uint256 numerator = (pAvg * FUNDING_GOAL) / 1e18;
            uint256 denominator = 1e18 - pAvg;
            uint256 expectedAlpha = (numerator * 1e18) / denominator;

            // Verify exact match (zero tolerance for mathematical correctness)
            assertEq(
                actualAlpha,
                expectedAlpha,
                string(abi.encodePacked(
                    "Alpha must match formula: alpha = (P_avg * x_fin)/(1-P_avg) for P_avg=",
                    vm.toString(pAvg / 1e15), // Convert to readable format
                    "/1000"
                ))
            );

            // Verify alpha is always positive (critical for curve calculations)
            assertGt(actualAlpha, 0, "Alpha must be positive for valid curve mathematics");
        }
    }

    /**
     * @notice Test verifying beta equals alpha for zero seed configuration
     * @dev In zero seed implementation, beta = alpha by design for mathematical consistency
     * Reference: docs/zero-seed-virtual-liquidity-mathematics.md Section 3
     */
    function test_BetaEqualsAlpha_ZeroSeedProperty() public {
        uint256[6] memory testPrices = [MIN_P_AVG, LOW_P_AVG, MID_P_AVG, HIGH_P_AVG, VERY_HIGH_P_AVG, MAX_P_AVG];

        for (uint256 i = 0; i < testPrices.length; i++) {
            uint256 pAvg = testPrices[i];

            vm.prank(owner);
            b3.setGoals(FUNDING_GOAL, pAvg);

            uint256 alpha = b3.alpha();
            uint256 beta = b3.beta();

            // Verify β = α (zero tolerance - must be exact)
            assertEq(
                beta,
                alpha,
                string(abi.encodePacked(
                    "Beta must equal alpha for zero seed (P_avg=",
                    vm.toString(pAvg / 1e15),
                    "/1000)"
                ))
            );

            // Verify both are positive
            assertGt(alpha, 0, "Alpha must be positive");
            assertGt(beta, 0, "Beta must be positive");
        }

        // Test with extreme values
        vm.prank(owner);
        b3.setGoals(100_000_000 * 1e18, MIN_P_AVG); // Large funding goal
        assertEq(b3.beta(), b3.alpha(), "Beta must equal alpha even with large funding goal");

        vm.prank(owner);
        b3.setGoals(1000 * 1e18, MAX_P_AVG); // Small funding goal, high P_avg
        assertEq(b3.beta(), b3.alpha(), "Beta must equal alpha even with small funding goal");
    }

    /**
     * @notice Test for initial virtualL calculation using formula: y_0 = k/alpha - alpha
     * @dev Validates the initial virtual L token amount matches the architectural formula
     * Reference: docs/zero-seed-virtual-liquidity-mathematics.md Section 5
     */
    function test_InitialVirtualL_FormulaValidation() public {
        uint256[6] memory testPrices = [MIN_P_AVG, LOW_P_AVG, MID_P_AVG, HIGH_P_AVG, VERY_HIGH_P_AVG, MAX_P_AVG];

        for (uint256 i = 0; i < testPrices.length; i++) {
            uint256 pAvg = testPrices[i];

            vm.prank(owner);
            b3.setGoals(FUNDING_GOAL, pAvg);

            uint256 alpha = b3.alpha();
            uint256 virtualK = b3.virtualK();
            (uint256 virtualInputTokens, uint256 virtualL,) = b3.getVirtualPair();

            // Verify initial state: virtualInputTokens must be 0 (zero seed enforcement)
            assertEq(
                virtualInputTokens,
                0,
                "Virtual input tokens must start at zero for zero seed"
            );

            // Calculate expected y_0 using formula: y_0 = k/alpha - alpha
            uint256 expectedVirtualL = virtualK / alpha - alpha;

            // Verify exact match
            assertEq(
                virtualL,
                expectedVirtualL,
                string(abi.encodePacked(
                    "Virtual L must match formula: y_0 = k/alpha - alpha for P_avg=",
                    vm.toString(pAvg / 1e15),
                    "/1000"
                ))
            );

            // Verify invariant: (x + alpha)(y + beta) = k at initialization
            // Since x_0 = 0 and beta = alpha: (0 + alpha)(y_0 + alpha) = k
            // Therefore: alpha(y_0 + alpha) = k
            // Note: Due to integer division rounding in y_0 = k/alpha - alpha,
            // we allow small tolerance for mathematical correctness
            uint256 invariantCheck = alpha * (virtualL + alpha);
            uint256 tolerance = virtualK / 1e12; // Very tight 0.0001% tolerance
            assertApproxEqAbs(
                invariantCheck,
                virtualK,
                tolerance,
                "Invariant (x+alpha)(y+beta)=k must hold at initialization within tolerance"
            );
        }
    }

    /**
     * @notice Test for first deposit when virtualInputTokens = 0
     * @dev Validates behavior of initial liquidity addition from zero state
     * Reference: docs/zero-seed-virtual-liquidity-mathematics.md Section 2.1
     */
    function test_FirstDeposit_FromZeroVirtualInputTokens() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, MID_P_AVG);

        // Verify initial state
        (uint256 initialVirtualInput, uint256 initialVirtualL,) = b3.getVirtualPair();
        assertEq(initialVirtualInput, 0, "Must start with zero virtual input tokens");

        uint256 firstDepositAmount = 1000 * 1e18;
        uint256 initialPrice = b3.getInitialMarginalPrice();
        uint256 alpha = b3.alpha();
        uint256 virtualK = b3.virtualK();

        // Perform first deposit
        deal(address(inputToken), user1, firstDepositAmount);
        vm.startPrank(user1);
        inputToken.approve(address(b3), firstDepositAmount);
        uint256 bondingTokensReceived = b3.addLiquidity(firstDepositAmount, 0);
        vm.stopPrank();

        // Verify bonding tokens were received
        assertGt(bondingTokensReceived, 0, "Should receive bonding tokens on first deposit");

        // Verify virtual input tokens updated correctly
        (uint256 newVirtualInput, uint256 newVirtualL,) = b3.getVirtualPair();
        assertEq(
            newVirtualInput,
            firstDepositAmount,
            "Virtual input tokens should equal first deposit amount"
        );

        // Verify price increased after first deposit
        uint256 newPrice = b3.getCurrentMarginalPrice();
        assertGt(newPrice, initialPrice, "Price must increase after first deposit");

        // Verify invariant still holds: (x + alpha)(y + beta) = k
        uint256 beta = b3.beta();
        uint256 invariantCheck = (newVirtualInput + alpha) * (newVirtualL + beta);
        // Allow small tolerance for rounding in state updates
        uint256 tolerance = virtualK / 1e18; // 0.0001% tolerance
        assertApproxEqAbs(
            invariantCheck,
            virtualK,
            tolerance,
            "Invariant must hold after first deposit"
        );

        // Verify price matches formula: P(x) = (x + alpha)^2 / k
        uint256 expectedPrice = ((newVirtualInput + alpha) * (newVirtualInput + alpha) * 1e18) / virtualK;
        assertApproxEqRel(
            newPrice,
            expectedPrice,
            1e15, // 0.1% tolerance
            "Price must match formula P(x) = (x+alpha)^2/k after first deposit"
        );
    }

    /**
     * @notice Test validating all virtual liquidity formulas match architectural documentation
     * @dev Comprehensive validation of all key formulas from architecture docs
     * Reference: docs/zero-seed-virtual-liquidity-mathematics.md Sections 1-7
     */
    function test_AllVirtualLiquidityFormulas_ArchitectureCompliance() public {
        vm.prank(owner);
        b3.setGoals(FUNDING_GOAL, MID_P_AVG);

        // FORMULA 1: Initial Price P_0 = P_avg^2
        assertEq(
            b3.getInitialMarginalPrice(),
            (MID_P_AVG * MID_P_AVG) / 1e18,
            "FORMULA 1: P_0 must equal P_avg^2 for zero seed"
        );

        // FORMULA 2: alpha = (P_avg * x_fin)/(1 - P_avg)
        assertEq(
            b3.alpha(),
            ((MID_P_AVG * FUNDING_GOAL) / 1e18 * 1e18) / (1e18 - MID_P_AVG),
            "FORMULA 2: alpha must equal (P_avg * x_fin)/(1 - P_avg)"
        );

        // FORMULA 3: beta = alpha
        assertEq(
            b3.beta(),
            b3.alpha(),
            "FORMULA 3: beta must equal alpha for zero seed"
        );

        // FORMULA 4: k = (x_fin + alpha)^2
        {
            uint256 alphaLocal = b3.alpha();
            assertEq(
                b3.virtualK(),
                (FUNDING_GOAL + alphaLocal) * (FUNDING_GOAL + alphaLocal),
                "FORMULA 4: k must equal (x_fin + alpha)^2"
            );
        }

        // FORMULA 5: y_0 = k/alpha - alpha
        {
            uint256 alphaLocal = b3.alpha();
            uint256 virtualKLocal = b3.virtualK();
            (, uint256 virtualL,) = b3.getVirtualPair();
            assertEq(
                virtualL,
                virtualKLocal / alphaLocal - alphaLocal,
                "FORMULA 5: y_0 must equal k/alpha - alpha"
            );
        }

        // FORMULA 6: x_0 = 0 (Zero Seed Enforcement)
        {
            (uint256 virtualInputTokens,,) = b3.getVirtualPair();
            assertEq(
                virtualInputTokens,
                0,
                "FORMULA 6: x_0 must be zero for zero seed enforcement"
            );
        }

        // FORMULA 7: (x + alpha)(y + beta) = k (Core Invariant)
        {
            uint256 alphaLocal = b3.alpha();
            uint256 betaLocal = b3.beta();
            uint256 virtualKLocal = b3.virtualK();
            (uint256 virtualInputTokens, uint256 virtualL,) = b3.getVirtualPair();
            // Note: Due to integer division rounding, allow small tolerance
            uint256 tolerance = virtualKLocal / 1e12; // Very tight 0.0001% tolerance
            assertApproxEqAbs(
                (virtualInputTokens + alphaLocal) * (virtualL + betaLocal),
                virtualKLocal,
                tolerance,
                "FORMULA 7: Core invariant (x+alpha)(y+beta)=k must hold within tolerance"
            );
        }

        // FORMULA 8: P(x) = (x + alpha)^2 / k (Marginal Price Function)
        {
            uint256 testAmount = FUNDING_GOAL / 10;
            deal(address(inputToken), user1, testAmount);
            vm.startPrank(user1);
            inputToken.approve(address(b3), testAmount);
            b3.addLiquidity(testAmount, 0);
            vm.stopPrank();

            uint256 alphaLocal = b3.alpha();
            uint256 virtualKLocal = b3.virtualK();
            (uint256 newVirtualInput,,) = b3.getVirtualPair();
            uint256 xPlusAlpha = newVirtualInput + alphaLocal;
            assertApproxEqRel(
                b3.getCurrentMarginalPrice(),
                (xPlusAlpha * xPlusAlpha * 1e18) / virtualKLocal,
                1e15, // 0.1% tolerance
                "FORMULA 8: P(x) must equal (x+alpha)^2/k"
            );
        }
    }

    /**
     * @notice Test for zero seed enforcement across optimized and general calculation paths
     * @dev Ensures zero seed is enforced consistently in all code paths
     * Reference: docs/zero-seed-virtual-liquidity-mathematics.md Section 2
     */
    function test_ZeroSeedEnforcement_AllCalculationPaths() public {
        // Test across different P_avg values
        uint256[6] memory testPrices = [MIN_P_AVG, LOW_P_AVG, MID_P_AVG, HIGH_P_AVG, VERY_HIGH_P_AVG, MAX_P_AVG];

        for (uint256 i = 0; i < testPrices.length; i++) {
            uint256 pAvg = testPrices[i];

            vm.prank(owner);
            b3.setGoals(FUNDING_GOAL, pAvg);

            // VERIFICATION 1: seedInput is immutably zero
            assertEq(b3.seedInput(), 0, "seedInput must always be zero");

            // VERIFICATION 2: virtualInputTokens starts at zero
            (uint256 virtualInputTokens,,) = b3.getVirtualPair();
            assertEq(virtualInputTokens, 0, "virtualInputTokens must start at zero");

            // VERIFICATION 3: getTotalRaised starts at zero
            assertEq(b3.getTotalRaised(), 0, "totalRaised must start at zero");

            // VERIFICATION 4: Initial price matches P_avg^2 (zero seed formula)
            uint256 initialPrice = b3.getInitialMarginalPrice();
            uint256 expectedPrice = (pAvg * pAvg) / 1e18;
            assertEq(
                initialPrice,
                expectedPrice,
                "Initial price must follow zero seed formula P_0=P_avg^2"
            );

            // VERIFICATION 5: Test quote functions respect zero seed
            uint256 quoteAmount = FUNDING_GOAL / 100;
            uint256 quotedTokens = b3.quoteAddLiquidity(quoteAmount);
            assertGt(quotedTokens, 0, "Quote should work correctly with zero seed");

            // VERIFICATION 6: Test actual liquidity addition from zero state
            deal(address(inputToken), user1, quoteAmount);
            vm.startPrank(user1);
            inputToken.approve(address(b3), quoteAmount);
            uint256 actualTokens = b3.addLiquidity(quoteAmount, 0);
            vm.stopPrank();

            assertGt(actualTokens, 0, "Should receive tokens when adding liquidity from zero state");

            // Verify virtualInputTokens updated correctly from zero
            (uint256 newVirtualInput,,) = b3.getVirtualPair();
            assertEq(
                newVirtualInput,
                quoteAmount,
                "Virtual input should equal deposit amount after first deposit from zero"
            );
        }

        // VERIFICATION 7: Test with different funding goals (optimized path variations)
        vm.prank(owner);
        b3.setGoals(1_000 * 1e18, MID_P_AVG); // Small
        assertEq(b3.seedInput(), 0, "Zero seed must be enforced for small funding goal");
        (uint256 vInput1,,) = b3.getVirtualPair();
        assertEq(vInput1, 0, "Zero virtual input must be enforced for small funding goal");

        vm.prank(owner);
        b3.setGoals(1_000_000 * 1e18, MID_P_AVG); // Medium
        assertEq(b3.seedInput(), 0, "Zero seed must be enforced for medium funding goal");
        (uint256 vInput2,,) = b3.getVirtualPair();
        assertEq(vInput2, 0, "Zero virtual input must be enforced for medium funding goal");

        vm.prank(owner);
        b3.setGoals(100_000_000 * 1e18, MID_P_AVG); // Large
        assertEq(b3.seedInput(), 0, "Zero seed must be enforced for large funding goal");
        (uint256 vInput3,,) = b3.getVirtualPair();
        assertEq(vInput3, 0, "Zero virtual input must be enforced for large funding goal");
    }
}
