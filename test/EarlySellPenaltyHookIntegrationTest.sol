// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/EarlySellPenaltyHook.sol";
import "../src/interfaces/IEarlySellPenaltyHook.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";

/**
 * @title EarlySellPenaltyHookIntegrationTest
 * @notice Comprehensive integration tests for EarlySellPenaltyHook implementation
 * @dev TDD Green Phase - Tests should now pass with the real implementation
 */
contract EarlySellPenaltyHookIntegrationTest is Test {
    Behodler3Tokenlaunch public b3;
    MockERC20 public inputToken;
    MockBondingToken public bondingToken;
    MockVault public vault;
    EarlySellPenaltyHook public penaltyHook;
    
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    uint256 constant INITIAL_INPUT_SUPPLY = 1000000 * 1e18;
    uint256 constant TYPICAL_INPUT_AMOUNT = 1000 * 1e18;
    uint256 constant ONE_HOUR = 3600;
    uint256 constant ONE_DAY = 24 * ONE_HOUR;
    
    function setUp() public {
        // Deploy mock contracts
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));
        
        // Deploy B3 contract
        vm.startPrank(owner);
        b3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)),
            IBondingToken(address(bondingToken)),
            IVault(address(vault))
        );
        
        // Deploy real penalty hook
        penaltyHook = new EarlySellPenaltyHook();
        vm.stopPrank();
        
        // Set the bonding curve address in the vault
        vault.setBondingCurve(address(b3));
        
        // Setup user balances
        inputToken.mint(user1, INITIAL_INPUT_SUPPLY);
        inputToken.mint(user2, INITIAL_INPUT_SUPPLY);
        
        // Approve spending
        vm.prank(user1);
        inputToken.approve(address(b3), type(uint256).max);
        vm.prank(user2);
        inputToken.approve(address(b3), type(uint256).max);
    }

    // ============ TIMESTAMP TRACKING TESTS ============
    
    function test_BuyerTimestampRecordedOnPurchase() public {
        // Set penalty hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        uint256 timestampBefore = block.timestamp;
        
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        uint256 recordedTimestamp = penaltyHook.getBuyerTimestamp(user1);
        
        assertGe(recordedTimestamp, timestampBefore, "Timestamp should be recorded for buyer");
        assertLe(recordedTimestamp, block.timestamp, "Timestamp should not be in future");
    }
    
    function test_TimestampUpdatedOnSubsequentBuy() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // First buy
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        uint256 firstTimestamp = penaltyHook.getBuyerTimestamp(user1);
        
        // Wait some time and buy again
        vm.warp(block.timestamp + ONE_HOUR);
        
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        uint256 secondTimestamp = penaltyHook.getBuyerTimestamp(user1);
        
        assertGt(secondTimestamp, firstTimestamp, "Timestamp should be updated on subsequent buy");
    }
    
    function test_DifferentBuyersHaveDifferentTimestamps() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // User1 buys first
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait and then user2 buys
        vm.warp(block.timestamp + ONE_HOUR);
        
        vm.prank(user2);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        uint256 timestamp1 = penaltyHook.getBuyerTimestamp(user1);
        uint256 timestamp2 = penaltyHook.getBuyerTimestamp(user2);
        
        assertLt(timestamp1, timestamp2, "Different buyers should have different timestamps");
    }
    
    function test_FirstTimeBuyerHasZeroTimestamp() public {
        uint256 timestamp = penaltyHook.getBuyerTimestamp(user1);
        assertEq(timestamp, 0, "First-time buyer should have zero timestamp");
    }

    // ============ FEE CALCULATION TESTS ============
    
    function test_ImmediateSellHasMaximumPenalty() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        uint256 baseOutputWithoutHook = b3.quoteRemoveLiquidity(bondingTokens);
        
        // Immediately sell (should get 100% penalty)
        vm.prank(user1);
        uint256 actualOutput = b3.removeLiquidity(bondingTokens, 0);
        
        // With 100% penalty, effective bonding tokens used should be 0, so output should be minimal
        assertLt(actualOutput, baseOutputWithoutHook, "Should receive less due to penalty");
        
        // Check penalty calculation directly
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFee, 1000, "Immediate sell should have maximum penalty (100%)");
    }
    
    function test_PenaltyDeclinesOverTime() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait 10 hours and check penalty (should have 90% penalty)
        vm.warp(block.timestamp + (10 * ONE_HOUR));
        
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFee, 900, "10-hour wait should result in 90% penalty");
        
        // Wait another 10 hours (20 hours total, should have 80% penalty)
        vm.warp(block.timestamp + (10 * ONE_HOUR));
        
        uint256 penaltyFee2 = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFee2, 800, "20-hour wait should result in 80% penalty");
    }
    
    function test_NoPenaltyAfter100Hours() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait 100+ hours and sell (should have no penalty)
        vm.warp(block.timestamp + (101 * ONE_HOUR));
        
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFee, 0, "Sell after max duration should have no penalty");
        
        // Verify selling actually works without penalty
        uint256 baseOutput = b3.quoteRemoveLiquidity(bondingTokens);
        vm.prank(user1);
        uint256 actualOutput = b3.removeLiquidity(bondingTokens, 0);
        
        assertEq(actualOutput, baseOutput, "Should receive full amount with no penalty");
    }
    
    function test_FirstTimeSellWithoutBuyHasMaxPenalty() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // Check penalty for user who never bought
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user2);
        assertEq(penaltyFee, 1000, "First-time seller should get maximum penalty");
    }

    // ============ CONFIGURATION TESTS ============
    
    function test_PenaltyParametersCanBeSet() public {
        vm.prank(owner);
        penaltyHook.setPenaltyParameters(15, 80); // 1.5% per hour, 80-hour max
        
        (uint256 declineRate, uint256 maxDuration, bool active) = penaltyHook.getPenaltyParameters();
        assertEq(declineRate, 15, "Decline rate should be updated");
        assertEq(maxDuration, 80, "Max duration should be updated");
        assertTrue(active, "Penalty should be active by default");
    }
    
    function test_PenaltyCanBeDeactivated() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // Deactivate penalty
        vm.prank(owner);
        penaltyHook.setPenaltyActive(false);
        
        // Buy and immediately sell
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        uint256 baseOutput = b3.quoteRemoveLiquidity(bondingTokens);
        
        vm.prank(user1);
        uint256 actualOutput = b3.removeLiquidity(bondingTokens, 0);
        
        assertEq(actualOutput, baseOutput, "Deactivated penalty should result in no fee");
        
        // Verify penalty calculation returns 0
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFee, 0, "Deactivated penalty should calculate 0 fee");
    }
    
    function test_CustomPenaltyRateWorks() public {
        // Set custom rate: 20 = 2% per hour, 50 hour max
        vm.prank(owner);
        penaltyHook.setPenaltyParameters(20, 50);
        
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait 5 hours and check penalty (should have 90% penalty with 2% decline rate)
        vm.warp(block.timestamp + (5 * ONE_HOUR));
        
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFee, 900, "Custom 2% rate should result in 90% penalty after 5 hours");
        
        // Wait until penalty should be zero (50 hours = 100% decline at 2% per hour)
        vm.warp(block.timestamp + (45 * ONE_HOUR)); // Total 50 hours
        
        uint256 penaltyFeeZero = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFeeZero, 0, "Penalty should be zero after max duration");
    }

    // ============ INTEGRATION TESTS ============
    
    function test_PenaltyHookIntegratesWithBehodler3() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // Verify hook is set
        assertEq(address(b3.getHook()), address(penaltyHook), "Hook should be set");
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Verify timestamp was recorded
        uint256 timestamp = penaltyHook.getBuyerTimestamp(user1);
        assertGt(timestamp, 0, "Timestamp should be recorded");
        
        // Sell tokens immediately and verify penalty is applied
        uint256 baseOutput = b3.quoteRemoveLiquidity(bondingTokens);
        
        vm.prank(user1);
        uint256 actualOutput = b3.removeLiquidity(bondingTokens, 0);
        
        assertLt(actualOutput, baseOutput, "Should receive less due to penalty");
    }
    
    function test_MultipleBuysSingleSell() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // First buy
        vm.prank(user1);
        uint256 bondingTokens1 = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        uint256 firstTimestamp = penaltyHook.getBuyerTimestamp(user1);
        
        // Wait and second buy (should reset timestamp)
        vm.warp(block.timestamp + (5 * ONE_HOUR));
        
        vm.prank(user1);
        uint256 bondingTokens2 = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        uint256 secondTimestamp = penaltyHook.getBuyerTimestamp(user1);
        
        assertGt(secondTimestamp, firstTimestamp, "Timestamp should be updated on second buy");
        
        // Immediately sell (penalty should be based on second buy)
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFee, 1000, "Penalty should be based on most recent buy");
    }

    // ============ EDGE CASE TESTS ============
    
    function test_ZeroAmountBuyDoesNotUpdateTimestamp() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        uint256 initialTimestamp = penaltyHook.getBuyerTimestamp(user1);
        
        // Try to buy with zero amount (should revert before hook is called)
        vm.prank(user1);
        vm.expectRevert("B3: Input amount must be greater than 0");
        b3.addLiquidity(0, 0);
        
        uint256 afterTimestamp = penaltyHook.getBuyerTimestamp(user1);
        
        assertEq(afterTimestamp, initialTimestamp, "Zero amount buy should not update timestamp");
    }
    
    function test_PenaltyAtExactHourBoundaries() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait exactly 1 hour
        vm.warp(block.timestamp + ONE_HOUR);
        
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFee, 990, "Exactly 1 hour should result in 99% penalty");
        
        // Wait exactly 100 hours
        vm.warp(block.timestamp + (99 * ONE_HOUR)); // Total 100 hours
        
        uint256 penaltyFeeAtMax = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFeeAtMax, 0, "Exactly 100 hours should result in 0% penalty");
    }

    // ============ OWNER ACCESS CONTROL TESTS ============
    
    function test_OnlyOwnerCanSetPenaltyParameters() public {
        vm.prank(user1);
        vm.expectRevert();
        penaltyHook.setPenaltyParameters(15, 80);
        
        // Owner should be able to set parameters
        vm.prank(owner);
        penaltyHook.setPenaltyParameters(15, 80);
        
        (uint256 declineRate, uint256 maxDuration,) = penaltyHook.getPenaltyParameters();
        assertEq(declineRate, 15, "Owner should be able to set decline rate");
        assertEq(maxDuration, 80, "Owner should be able to set max duration");
    }
    
    function test_OnlyOwnerCanTogglePenaltyStatus() public {
        vm.prank(user1);
        vm.expectRevert();
        penaltyHook.setPenaltyActive(false);
        
        // Owner should be able to toggle status
        vm.prank(owner);
        penaltyHook.setPenaltyActive(false);
        
        (,, bool active) = penaltyHook.getPenaltyParameters();
        assertFalse(active, "Owner should be able to deactivate penalty");
    }

    // ============ PARAMETER VALIDATION TESTS ============
    
    function test_PenaltyParametersValidation() public {
        // Should revert with zero decline rate
        vm.prank(owner);
        vm.expectRevert("EarlySellPenaltyHook: Decline rate must be greater than 0");
        penaltyHook.setPenaltyParameters(0, 100);
        
        // Should revert with zero max duration
        vm.prank(owner);
        vm.expectRevert("EarlySellPenaltyHook: Max duration must be greater than 0");
        penaltyHook.setPenaltyParameters(10, 0);
        
        // Should revert if parameters don't allow penalty to reach zero
        vm.prank(owner);
        vm.expectRevert("EarlySellPenaltyHook: Parameters must allow penalty to reach 0");
        penaltyHook.setPenaltyParameters(5, 100); // 5 * 100 = 500, less than 1000
    }

    // ============ EVENT EMISSION TESTS ============
    
    function test_BuyerTimestampRecordedEventEmitted() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        vm.expectEmit(true, false, false, true);
        emit BuyerTimestampRecorded(user1, block.timestamp);
        
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
    }
    
    function test_PenaltyAppliedEventEmitted() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait 2 hours
        vm.warp(block.timestamp + (2 * ONE_HOUR));
        
        vm.expectEmit(true, false, false, true);
        emit PenaltyApplied(user1, 980, 2);
        
        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);
    }
    
    function test_PenaltyParametersUpdatedEventEmitted() public {
        vm.expectEmit(false, false, false, true);
        emit PenaltyParametersUpdated(15, 80);
        
        vm.prank(owner);
        penaltyHook.setPenaltyParameters(15, 80);
    }
    
    function test_PenaltyStatusChangedEventEmitted() public {
        vm.expectEmit(false, false, false, true);
        emit PenaltyStatusChanged(false);
        
        vm.prank(owner);
        penaltyHook.setPenaltyActive(false);
    }

    // ============ SCENARIO TESTS ============
    
    function test_CompleteScenario_BuyWaitSellWithPenalty() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        uint256 initialBalance = inputToken.balanceOf(user1);
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait 25 hours (should have 75% penalty)
        vm.warp(block.timestamp + (25 * ONE_HOUR));
        
        // Sell tokens
        vm.prank(user1);
        uint256 outputReceived = b3.removeLiquidity(bondingTokens, 0);
        
        uint256 finalBalance = inputToken.balanceOf(user1);
        uint256 totalReceived = finalBalance - (initialBalance - TYPICAL_INPUT_AMOUNT);
        
        assertEq(totalReceived, outputReceived, "Balance should reflect output received");
        assertLt(totalReceived, TYPICAL_INPUT_AMOUNT, "Should receive less than input due to penalty");
        
        // Verify penalty was 75%
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user1);
        assertEq(penaltyFee, 750, "25-hour wait should result in 75% penalty");
    }

    // ============ EVENT DEFINITIONS FOR COMPILATION ============
    
    event BuyerTimestampRecorded(address indexed buyer, uint256 timestamp);
    event PenaltyApplied(address indexed seller, uint256 penaltyFee, uint256 hoursElapsed);
    event PenaltyParametersUpdated(uint256 declineRatePerHour, uint256 maxDurationHours);
    event PenaltyStatusChanged(bool active);
}