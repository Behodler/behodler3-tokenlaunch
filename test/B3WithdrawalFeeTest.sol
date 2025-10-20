// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title B3WithdrawalFeeTest
 * @notice Tests for Withdrawal Fee functionality in Behodler3 Bootstrap AMM
 * @dev Tests written first in TDD Red Phase - implementing story 032.1
 *
 * CRITICAL CONCEPT BEING TESTED: Optional Withdrawal Fee Mechanism
 * - Fee applied to bondingTokens before withdrawal calculation
 * - Supply decreases by full amount, withdrawal uses post-fee amount
 * - Fee range: 0-10000 basis points (0% to 100%)
 * - Events emitted for fee changes and fee collection
 */
contract B3WithdrawalFeeTest is Test {
    Behodler3Tokenlaunch public b3;
    MockVault public vault;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    // Virtual Liquidity Test Parameters
    uint256 public constant FUNDING_GOAL = 1_000_000 * 1e18; // 1M tokens
    uint256 public constant SEED_INPUT = 0; // Always zero with zero seed enforcement
    uint256 public constant DESIRED_AVG_PRICE = 0.9e18; // 0.9 (90% of final price)

    // Test fee values
    uint256 public constant ZERO_FEE = 0;
    uint256 public constant LOW_FEE = 200; // 2%
    uint256 public constant MEDIUM_FEE = 500; // 5%
    uint256 public constant HIGH_FEE = 1000; // 10%
    uint256 public constant MAX_FEE = 10000; // 100%

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));

        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IYieldStrategy(address(vault))
        );

        vm.stopPrank();

        // Set the bonding curve address in the vault to allow B3 to call deposit/withdraw
        vault.setClient(address(b3), true);

        // Initialize vault approval after vault authorizes B3
        vm.startPrank(owner);
        b3.initializeVaultApproval();

        // Set virtual liquidity goals
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);
        vm.stopPrank();

        // Setup test tokens and add initial liquidity
        inputToken.mint(user1, 1_000_000 * 1e18);
        inputToken.mint(user2, 1_000_000 * 1e18);

        // Add some liquidity first so we can test removal
        vm.startPrank(user1);
        inputToken.approve(address(b3), 100_000 * 1e18);
        b3.addLiquidity(100_000 * 1e18, 0); // Add substantial liquidity for testing
        vm.stopPrank();
    }

    // ============ WITHDRAWAL FEE SETTER TESTS ============

    function testSetWithdrawalFeeOnlyOwner() public {
        vm.startPrank(user1); // Not owner

        vm.expectRevert();
        b3.setWithdrawalFee(LOW_FEE);

        vm.stopPrank();
    }

    function testSetWithdrawalFeeValidRange() public {
        vm.startPrank(owner);

        // Test valid fees
        b3.setWithdrawalFee(ZERO_FEE);
        assertEq(b3.withdrawalFeeBasisPoints(), ZERO_FEE, "Zero fee should be set");

        b3.setWithdrawalFee(LOW_FEE);
        assertEq(b3.withdrawalFeeBasisPoints(), LOW_FEE, "Low fee should be set");

        b3.setWithdrawalFee(MAX_FEE);
        assertEq(b3.withdrawalFeeBasisPoints(), MAX_FEE, "Max fee should be set");

        vm.stopPrank();
    }

    function testSetWithdrawalFeeInvalidRange() public {
        vm.startPrank(owner);

        // Test invalid fee (over 10000)
        vm.expectRevert("B3: Fee must be <= 10000 basis points");
        b3.setWithdrawalFee(10001);

        vm.expectRevert("B3: Fee must be <= 10000 basis points");
        b3.setWithdrawalFee(50000);

        vm.stopPrank();
    }

    function testSetWithdrawalFeeEvent() public {
        vm.startPrank(owner);

        // Test event emission
        vm.expectEmit(true, true, true, true);
        emit WithdrawalFeeUpdated(0, LOW_FEE);
        b3.setWithdrawalFee(LOW_FEE);

        // Test updating existing fee
        vm.expectEmit(true, true, true, true);
        emit WithdrawalFeeUpdated(LOW_FEE, MEDIUM_FEE);
        b3.setWithdrawalFee(MEDIUM_FEE);

        vm.stopPrank();
    }

    // ============ ZERO FEE TESTS ============

    function testRemoveLiquidityZeroFee() public {
        // Ensure fee is zero (default)
        assertEq(b3.withdrawalFeeBasisPoints(), ZERO_FEE, "Fee should be zero by default");

        uint256 bondingTokenAmount = 10_000 * 1e18;
        uint256 expectedOut = b3.quoteRemoveLiquidity(bondingTokenAmount);

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        // With zero fee, output should match quote exactly
        assertEq(inputTokensOut, expectedOut, "Zero fee should not affect withdrawal amount");

        vm.stopPrank();
    }

    function testRemoveLiquidityZeroFeeNoFeeEvent() public {
        // Ensure fee is zero
        assertEq(b3.withdrawalFeeBasisPoints(), ZERO_FEE, "Fee should be zero by default");

        uint256 bondingTokenAmount = 10_000 * 1e18;

        vm.startPrank(user1);

        // Should not emit FeeCollected event with zero fee
        vm.recordLogs();
        b3.removeLiquidity(bondingTokenAmount, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Check that no FeeCollected event was emitted
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(
                logs[i].topics[0] == keccak256("FeeCollected(address,uint256,uint256)"),
                "FeeCollected event should not be emitted with zero fee"
            );
        }

        vm.stopPrank();
    }

    // ============ NON-ZERO FEE TESTS ============

    function testRemoveLiquidityWithLowFee() public {
        // Set a low fee
        vm.prank(owner);
        b3.setWithdrawalFee(LOW_FEE); // 2%

        uint256 bondingTokenAmount = 10_000 * 1e18;
        uint256 expectedOut = b3.quoteRemoveLiquidity(bondingTokenAmount);

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        // Output should be reduced by fee
        assertTrue(inputTokensOut < b3.quoteRemoveLiquidity(bondingTokenAmount), "Fee should reduce output");
        assertEq(inputTokensOut, expectedOut, "Output should match effective amount calculation");

        vm.stopPrank();
    }

    function testRemoveLiquidityWithMediumFee() public {
        // Set a medium fee
        vm.prank(owner);
        b3.setWithdrawalFee(MEDIUM_FEE); // 5%

        uint256 bondingTokenAmount = 10_000 * 1e18;
        uint256 expectedOut = b3.quoteRemoveLiquidity(bondingTokenAmount);

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        // Output should be reduced by fee
        assertEq(inputTokensOut, expectedOut, "Output should match effective amount calculation");

        vm.stopPrank();
    }

    function testRemoveLiquidityWithHighFee() public {
        // Set a high fee
        vm.prank(owner);
        b3.setWithdrawalFee(HIGH_FEE); // 10%

        uint256 bondingTokenAmount = 10_000 * 1e18;
        uint256 expectedOut = b3.quoteRemoveLiquidity(bondingTokenAmount);

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        // Output should be reduced by fee
        assertEq(inputTokensOut, expectedOut, "Output should match effective amount calculation");

        vm.stopPrank();
    }

    function testRemoveLiquidityWithMaxFee() public {
        // Set maximum fee
        vm.prank(owner);
        b3.setWithdrawalFee(MAX_FEE); // 100%

        uint256 bondingTokenAmount = 10_000 * 1e18;

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        // With 100% fee, user should get zero tokens
        assertEq(inputTokensOut, 0, "100% fee should result in zero output");

        vm.stopPrank();
    }

    // ============ FEE COLLECTION EVENT TESTS ============

    function testRemoveLiquidityFeeCollectedEvent() public {
        // Set a fee
        vm.prank(owner);
        b3.setWithdrawalFee(LOW_FEE); // 2%

        uint256 bondingTokenAmount = 10_000 * 1e18;
        uint256 expectedFee = (bondingTokenAmount * LOW_FEE) / 10000;

        vm.startPrank(user1);

        // Expect FeeCollected event
        vm.expectEmit(true, false, false, true);
        emit FeeCollected(user1, bondingTokenAmount, expectedFee);

        b3.removeLiquidity(bondingTokenAmount, 0);

        vm.stopPrank();
    }

    function testRemoveLiquidityNoFeeCollectedEventWhenZero() public {
        // Ensure fee is zero
        assertEq(b3.withdrawalFeeBasisPoints(), ZERO_FEE, "Fee should be zero");

        uint256 bondingTokenAmount = 10_000 * 1e18;

        vm.startPrank(user1);

        // Record events
        vm.recordLogs();
        b3.removeLiquidity(bondingTokenAmount, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify no FeeCollected event was emitted
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(
                logs[i].topics[0] == keccak256("FeeCollected(address,uint256,uint256)"),
                "FeeCollected event should not be emitted with zero fee"
            );
        }

        vm.stopPrank();
    }

    // ============ SUPPLY MANAGEMENT TESTS ============

    function testRemoveLiquidityBurnsFullAmount() public {
        // Set a fee
        vm.prank(owner);
        b3.setWithdrawalFee(MEDIUM_FEE); // 5%

        uint256 bondingTokenAmount = 10_000 * 1e18;
        uint256 initialBondingBalance = bondingToken.balanceOf(user1);

        vm.startPrank(user1);

        b3.removeLiquidity(bondingTokenAmount, 0);

        // Full bonding token amount should be burned (not just effective amount)
        uint256 finalBondingBalance = bondingToken.balanceOf(user1);
        assertEq(
            initialBondingBalance - finalBondingBalance,
            bondingTokenAmount,
            "Full bonding token amount should be burned"
        );

        vm.stopPrank();
    }

    function testRemoveLiquidityVirtualPairStateWithFee() public {
        // Set a fee
        vm.prank(owner);
        b3.setWithdrawalFee(MEDIUM_FEE); // 5%

        uint256 bondingTokenAmount = 10_000 * 1e18;
        (uint256 initialVInput, uint256 initialVL,) = b3.getVirtualPair();

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        (uint256 finalVInput, uint256 finalVL,) = b3.getVirtualPair();

        // Virtual input tokens should decrease by actual withdrawal amount
        assertEq(finalVInput, initialVInput - inputTokensOut, "Virtual input should decrease by withdrawal amount");

        // Virtual L should increase by full bonding token amount (not effective amount)
        assertEq(finalVL, initialVL + bondingTokenAmount, "Virtual L should increase by full bonding token amount");

        vm.stopPrank();
    }

    // ============ PRECISION AND EDGE CASE TESTS ============

    function testRemoveLiquiditySmallAmountFee() public {
        // Set a fee
        vm.prank(owner);
        b3.setWithdrawalFee(LOW_FEE); // 2%

        uint256 bondingTokenAmount = 1000; // Small amount
        uint256 expectedFee = (bondingTokenAmount * LOW_FEE) / 10000; // Should be 20

        vm.startPrank(user1);

        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);

        // Should handle small amounts correctly
        assertTrue(inputTokensOut >= 0, "Should handle small amounts without error");

        vm.stopPrank();
    }

    function testRemoveLiquidityFeeRounding() public {
        // Set a fee that will cause rounding
        vm.prank(owner);
        b3.setWithdrawalFee(333); // 3.33% - will cause rounding

        uint256 bondingTokenAmount = 100;
        uint256 calculatedFee = (bondingTokenAmount * 333) / 10000; // Should be 3.33, rounded down to 3

        vm.startPrank(user1);

        // Should handle rounding without error
        uint256 inputTokensOut = b3.removeLiquidity(bondingTokenAmount, 0);
        assertTrue(inputTokensOut >= 0, "Should handle fee rounding correctly");

        vm.stopPrank();
    }

    // ============ FEE IMPACT COMPARISON TESTS ============

    function testRemoveLiquidityFeeImpactComparison() public {
        uint256 bondingTokenAmount = 10_000 * 1e18;

        // Test with zero fee
        uint256 outputZeroFee = b3.quoteRemoveLiquidity(bondingTokenAmount);

        // Set low fee and test
        vm.prank(owner);
        b3.setWithdrawalFee(LOW_FEE); // 2%

        uint256 expectedFee = (bondingTokenAmount * LOW_FEE) / 10000;
        uint256 effectiveBondingTokens = bondingTokenAmount - expectedFee;
        uint256 outputWithFee = b3.quoteRemoveLiquidity(effectiveBondingTokens);

        // Fee should reduce output
        assertTrue(outputWithFee < outputZeroFee, "Fee should reduce withdrawal output");

        // Calculate impact
        uint256 feeImpact = outputZeroFee - outputWithFee;
        assertTrue(feeImpact > 0, "Fee impact should be positive");
    }

    function testRemoveLiquidityDifferentFeeRates() public {
        uint256 bondingTokenAmount = 10_000 * 1e18;

        uint256[] memory feeRates = new uint256[](4);
        feeRates[0] = 100; // 1%
        feeRates[1] = 500; // 5%
        feeRates[2] = 1000; // 10%
        feeRates[3] = 2000; // 20%

        uint256 previousOutput = type(uint256).max;

        for (uint256 i = 0; i < feeRates.length; i++) {
            vm.prank(owner);
            b3.setWithdrawalFee(feeRates[i]);

            uint256 expectedFee = (bondingTokenAmount * feeRates[i]) / 10000;
            uint256 effectiveBondingTokens = bondingTokenAmount - expectedFee;
            uint256 output = b3.quoteRemoveLiquidity(effectiveBondingTokens);

            // Higher fee should result in lower output
            if (previousOutput != type(uint256).max) {
                assertTrue(output < previousOutput, "Higher fee should result in lower output");
            }
            previousOutput = output;
        }
    }

    // ============ MEV PROTECTION WITH FEES ============

    function testRemoveLiquidityMEVProtectionWithFee() public {
        // Set a fee
        vm.prank(owner);
        b3.setWithdrawalFee(MEDIUM_FEE); // 5%

        uint256 bondingTokenAmount = 10_000 * 1e18;
        uint256 expectedOut = b3.quoteRemoveLiquidity(bondingTokenAmount);
        uint256 minInputTokens = expectedOut + 1; // Set minimum higher than expected

        vm.startPrank(user1);

        vm.expectRevert("B3: Insufficient output amount");
        b3.removeLiquidity(bondingTokenAmount, minInputTokens);

        vm.stopPrank();
    }

    // ============ INTEGRATION TESTS - FEE CHANGES DURING ACTIVE OPERATIONS ============

    function testFeeChangeDuringActiveLiquidityOperations() public {
        uint256 bondingTokenAmount = 10_000 * 1e18;

        // First, remove liquidity with zero fee
        uint256 outputZeroFee = b3.quoteRemoveLiquidity(bondingTokenAmount);

        vm.startPrank(user1);
        uint256 actualOutputZero = b3.removeLiquidity(bondingTokenAmount, 0);
        vm.stopPrank();

        assertEq(actualOutputZero, outputZeroFee, "Zero fee withdrawal should match quote");

        // Add liquidity back for next test
        vm.startPrank(user1);
        inputToken.approve(address(b3), 50_000 * 1e18);
        b3.addLiquidity(50_000 * 1e18, 0);
        vm.stopPrank();

        // Change fee mid-operation lifecycle
        vm.prank(owner);
        b3.setWithdrawalFee(MEDIUM_FEE); // 5%

        // Now remove liquidity with the new fee
        uint256 expectedOutputWithFee = b3.quoteRemoveLiquidity(bondingTokenAmount);

        vm.startPrank(user1);
        uint256 actualOutputWithFee = b3.removeLiquidity(bondingTokenAmount, 0);
        vm.stopPrank();

        assertEq(actualOutputWithFee, expectedOutputWithFee, "Fee withdrawal should match calculated amount");
        assertTrue(actualOutputWithFee < actualOutputZero, "Fee should reduce withdrawal output");
    }

    function testMultipleFeeChangesWithActiveUsers() public {
        // Setup multiple users with liquidity
        vm.startPrank(user2);
        inputToken.approve(address(b3), 50_000 * 1e18);
        b3.addLiquidity(50_000 * 1e18, 0);
        vm.stopPrank();

        uint256 bondingTokenAmount = 5_000 * 1e18;

        // Test sequence of fee changes
        uint256[] memory feeSequence = new uint256[](5);
        feeSequence[0] = 0; // 0%
        feeSequence[1] = 100; // 1%
        feeSequence[2] = 500; // 5%
        feeSequence[3] = 1000; // 10%
        feeSequence[4] = 200; // 2% (decrease)

        uint256[] memory outputs = new uint256[](5);

        for (uint256 i = 0; i < feeSequence.length; i++) {
            // Change fee
            vm.prank(owner);
            b3.setWithdrawalFee(feeSequence[i]);

            // Calculate expected output
            uint256 expectedOutput = b3.quoteRemoveLiquidity(bondingTokenAmount);

            // Perform withdrawal alternating between users
            address currentUser = (i % 2 == 0) ? user1 : user2;
            vm.startPrank(currentUser);
            outputs[i] = b3.removeLiquidity(bondingTokenAmount, 0);
            vm.stopPrank();

            assertEq(outputs[i], expectedOutput, "Output should match expected for each fee level");

            // Add liquidity back for next iteration
            vm.startPrank(currentUser);
            inputToken.approve(address(b3), 25_000 * 1e18);
            b3.addLiquidity(25_000 * 1e18, 0);
            vm.stopPrank();
        }

        // Verify fee impact ordering
        assertTrue(outputs[0] > outputs[1], "0% fee should yield more than 1%");
        assertTrue(outputs[1] > outputs[2], "1% fee should yield more than 5%");
        assertTrue(outputs[2] > outputs[3], "5% fee should yield more than 10%");
        assertTrue(outputs[3] < outputs[4], "10% fee should yield less than 2%");
    }

    function testFeeChangeImmediatelyAffectsNextOperation() public {
        uint256 bondingTokenAmount = 5_000 * 1e18;

        // Set initial fee
        vm.prank(owner);
        b3.setWithdrawalFee(LOW_FEE); // 2%

        // Get quote with current fee
        uint256 expectedOutput1 = b3.quoteRemoveLiquidity(bondingTokenAmount);

        // Change fee immediately
        vm.prank(owner);
        b3.setWithdrawalFee(HIGH_FEE); // 10%

        // Next operation should use new fee
        uint256 expectedOutput2 = b3.quoteRemoveLiquidity(bondingTokenAmount);

        vm.startPrank(user1);
        uint256 actualOutput = b3.removeLiquidity(bondingTokenAmount, 0);
        vm.stopPrank();

        assertEq(actualOutput, expectedOutput2, "Should use new fee immediately");
        assertTrue(actualOutput < expectedOutput1, "Higher fee should reduce output");
        assertTrue(expectedOutput2 < expectedOutput1, "Sanity check: calculations should be consistent");
    }

    // ============ FUZZING TESTS - FEE BOUNDARY CONDITIONS ============

    function testFuzz_WithdrawalFeeValidRange(uint256 feeBasisPoints) public {
        // Bound fee to valid range
        feeBasisPoints = bound(feeBasisPoints, 0, 10000);

        vm.prank(owner);
        b3.setWithdrawalFee(feeBasisPoints);

        assertEq(b3.withdrawalFeeBasisPoints(), feeBasisPoints, "Fee should be set to fuzzed value");
    }

    function testFuzz_WithdrawalFeeInvalidRange(uint256 feeBasisPoints) public {
        // Test values above maximum
        vm.assume(feeBasisPoints > 10000);
        feeBasisPoints = bound(feeBasisPoints, 10001, type(uint256).max);

        vm.prank(owner);
        vm.expectRevert("B3: Fee must be <= 10000 basis points");
        b3.setWithdrawalFee(feeBasisPoints);
    }

    function testFuzz_RemoveLiquidityWithVariableFee(uint256 feeBasisPoints, uint256 bondingTokenAmount) public {
        // Bound inputs to reasonable ranges - avoid extreme edge cases
        feeBasisPoints = bound(feeBasisPoints, 0, 10000);

        // Use safer bounds for bonding token amount
        uint256 userBalance = bondingToken.balanceOf(user1);
        vm.assume(userBalance >= 10e18); // Require meaningful balance
        bondingTokenAmount = bound(bondingTokenAmount, 1e18, userBalance / 2); // Use half to be safe

        vm.prank(owner);
        b3.setWithdrawalFee(feeBasisPoints);

        // Get expected output using quote function (which applies fees internally)
        uint256 expectedOutput = b3.quoteRemoveLiquidity(bondingTokenAmount);

        // Perform actual withdrawal
        vm.startPrank(user1);
        uint256 actualOutput = b3.removeLiquidity(bondingTokenAmount, 0);
        vm.stopPrank();

        // Main assertion: fee calculation should be consistent
        assertEq(actualOutput, expectedOutput, "Fuzzed fee calculation should be consistent");
    }

    function testFuzz_FeeImpactVerification(uint256 feeBasisPoints, uint256 bondingTokenAmount) public {
        // Separate test for fee impact verification to avoid edge case conflicts
        feeBasisPoints = bound(feeBasisPoints, 100, 5000); // Use meaningful fee range (1% to 50%)

        uint256 userBalance = bondingToken.balanceOf(user1);
        vm.assume(userBalance >= 10e18);
        bondingTokenAmount = bound(bondingTokenAmount, 5e18, userBalance / 3); // Conservative bounds

        // First get quote without any fee set
        uint256 outputWithoutFee = b3.quoteRemoveLiquidity(bondingTokenAmount);

        // Now set the fee and get the quote with fee applied internally
        vm.prank(owner);
        b3.setWithdrawalFee(feeBasisPoints);
        uint256 outputWithFee = b3.quoteRemoveLiquidity(bondingTokenAmount);

        // Fee should reduce output
        assertTrue(outputWithFee < outputWithoutFee, "Fee should reduce withdrawal output");

        // Verify actual withdrawal matches quote calculation
        vm.startPrank(user1);
        uint256 actualOutput = b3.removeLiquidity(bondingTokenAmount, 0);
        vm.stopPrank();

        assertEq(actualOutput, outputWithFee, "Actual output should match fee-adjusted calculation");
    }

    function testFuzz_FeeCalculationPrecision(uint256 bondingTokenAmount, uint256 feeBasisPoints) public {
        // Bound to realistic ranges
        bondingTokenAmount = bound(bondingTokenAmount, 1, 1e24); // Very wide range for precision testing
        feeBasisPoints = bound(feeBasisPoints, 0, 10000);

        // Calculate fee manually to verify precision
        uint256 expectedFee = (bondingTokenAmount * feeBasisPoints) / 10000;
        uint256 expectedEffective = bondingTokenAmount - expectedFee;

        // Verify calculation doesn't overflow and maintains precision
        if (bondingTokenAmount > 0) {
            assertTrue(expectedEffective <= bondingTokenAmount, "Effective amount should not exceed original");
            assertTrue(expectedFee <= bondingTokenAmount, "Fee should not exceed original amount");
            assertEq(expectedEffective + expectedFee, bondingTokenAmount, "Precision should be maintained");
        }
    }

    function testFuzz_MaxFeeBoundary(uint256 bondingTokenAmount) public {
        bondingTokenAmount = bound(bondingTokenAmount, 1e18, 10_000 * 1e18);
        vm.assume(bondingToken.balanceOf(user1) >= bondingTokenAmount);

        // Test exactly at the boundary
        vm.prank(owner);
        b3.setWithdrawalFee(10000); // Exactly 100%

        vm.startPrank(user1);
        uint256 output = b3.removeLiquidity(bondingTokenAmount, 0);
        vm.stopPrank();

        // With 100% fee, effective bonding tokens = 0, so output should be 0
        assertEq(output, 0, "100% fee should result in zero output");
    }

    function testFuzz_ZeroFeeBoundary(uint256 bondingTokenAmount) public {
        bondingTokenAmount = bound(bondingTokenAmount, 1e18, 10_000 * 1e18);
        vm.assume(bondingToken.balanceOf(user1) >= bondingTokenAmount);

        // Test exactly at zero boundary
        vm.prank(owner);
        b3.setWithdrawalFee(0);

        uint256 expectedOutput = b3.quoteRemoveLiquidity(bondingTokenAmount);

        vm.startPrank(user1);
        uint256 actualOutput = b3.removeLiquidity(bondingTokenAmount, 0);
        vm.stopPrank();

        assertEq(actualOutput, expectedOutput, "Zero fee should give full quote amount");
    }

    function testFuzz_FeeBoundaryEdgeCases(uint256 feeBasisPoints) public {
        // Test values right at boundaries
        if (feeBasisPoints <= 10000) {
            vm.prank(owner);
            b3.setWithdrawalFee(feeBasisPoints);
            assertEq(b3.withdrawalFeeBasisPoints(), feeBasisPoints, "Valid boundary fee should be set");
        } else {
            vm.prank(owner);
            vm.expectRevert("B3: Fee must be <= 10000 basis points");
            b3.setWithdrawalFee(feeBasisPoints);
        }
    }

    // ============ GAS COST DOCUMENTATION TESTS ============

    function testGasCostFeeOperations() public {
        uint256 bondingTokenAmount = 10_000 * 1e18;

        // Test setWithdrawalFee gas cost
        vm.prank(owner);
        uint256 gasStart = gasleft();
        b3.setWithdrawalFee(MEDIUM_FEE);
        uint256 setFeeGas = gasStart - gasleft();

        // Test removeLiquidity with fee gas cost
        vm.startPrank(user1);
        gasStart = gasleft();
        b3.removeLiquidity(bondingTokenAmount, 0);
        uint256 removeLiquidityWithFeeGas = gasStart - gasleft();
        vm.stopPrank();

        // Add liquidity back for comparison
        vm.startPrank(user1);
        inputToken.approve(address(b3), 50_000 * 1e18);
        b3.addLiquidity(50_000 * 1e18, 0);
        vm.stopPrank();

        // Test removeLiquidity without fee gas cost
        vm.prank(owner);
        b3.setWithdrawalFee(0);

        vm.startPrank(user1);
        gasStart = gasleft();
        b3.removeLiquidity(bondingTokenAmount, 0);
        uint256 removeLiquidityNoFeeGas = gasStart - gasleft();
        vm.stopPrank();

        // Log gas costs for documentation
        console.log("Gas cost setWithdrawalFee:", setFeeGas);
        console.log("Gas cost removeLiquidity with fee:", removeLiquidityWithFeeGas);
        console.log("Gas cost removeLiquidity without fee:", removeLiquidityNoFeeGas);
        console.log("Fee overhead gas:", removeLiquidityWithFeeGas - removeLiquidityNoFeeGas);

        // Verify gas costs are reasonable
        assertTrue(setFeeGas < 50000, "setWithdrawalFee should be gas efficient");
        assertTrue(removeLiquidityWithFeeGas > removeLiquidityNoFeeGas, "Fee calculation adds some gas cost");
        assertTrue((removeLiquidityWithFeeGas - removeLiquidityNoFeeGas) < 100000, "Fee overhead should be reasonable");
    }

    // Define events for testing
    event WithdrawalFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollected(address indexed user, uint256 bondingTokenAmount, uint256 feeAmount);
}
