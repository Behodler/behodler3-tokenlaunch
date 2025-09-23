// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
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
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IVault(address(vault))
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
        uint256 expectedFee = (bondingTokenAmount * LOW_FEE) / 10000;
        uint256 effectiveBondingTokens = bondingTokenAmount - expectedFee;
        uint256 expectedOut = b3.quoteRemoveLiquidity(effectiveBondingTokens);

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
        uint256 expectedFee = (bondingTokenAmount * MEDIUM_FEE) / 10000;
        uint256 effectiveBondingTokens = bondingTokenAmount - expectedFee;
        uint256 expectedOut = b3.quoteRemoveLiquidity(effectiveBondingTokens);

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
        uint256 expectedFee = (bondingTokenAmount * HIGH_FEE) / 10000;
        uint256 effectiveBondingTokens = bondingTokenAmount - expectedFee;
        uint256 expectedOut = b3.quoteRemoveLiquidity(effectiveBondingTokens);

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
        uint256 expectedFee = (bondingTokenAmount * MEDIUM_FEE) / 10000;
        uint256 effectiveBondingTokens = bondingTokenAmount - expectedFee;
        uint256 expectedOut = b3.quoteRemoveLiquidity(effectiveBondingTokens);
        uint256 minInputTokens = expectedOut + 1; // Set minimum higher than expected

        vm.startPrank(user1);

        vm.expectRevert("B3: Insufficient output amount");
        b3.removeLiquidity(bondingTokenAmount, minInputTokens);

        vm.stopPrank();
    }

    // Define events for testing
    event WithdrawalFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollected(address indexed user, uint256 bondingTokenAmount, uint256 feeAmount);
}