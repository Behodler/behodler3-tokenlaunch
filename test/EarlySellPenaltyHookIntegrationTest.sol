// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/EarlySellPenaltyHook.sol";
import "../src/interfaces/IEarlySellPenaltyHook.sol";
import "../src/mocks/MockERC20.sol";
import "@vault/mocks/MockVault.sol";
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
        vault.setClient(address(b3), true);

        // Initialize vault approval after vault authorizes B3
        vm.startPrank(owner);
        b3.initializeVaultApproval();
        vm.stopPrank();

        // Setup user balances
        inputToken.mint(user1, INITIAL_INPUT_SUPPLY);
        inputToken.mint(user2, INITIAL_INPUT_SUPPLY);
        
        // Approve spending
        vm.prank(user1);
        inputToken.approve(address(b3), type(uint256).max);
        vm.prank(user2);
        inputToken.approve(address(b3), type(uint256).max);
    }
    
    /**
     * @notice Helper function to set up a non-all-time-high scenario
     * @dev First buyer pushes to all-time high and gets exemption, then sells everything.
     *      Second buyer purchases at lower price (not all-time high) and gets normal penalty.
     * @param testUser The user that should have normal penalty behavior
     * @return bondingTokens The amount of bonding tokens the test user received
     */
    function _setupNonAllTimeHighScenario(address testUser) internal returns (uint256 bondingTokens) {
        // Set penalty hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // First user buys to establish all-time high and verify zero penalty
        vm.prank(user1);
        uint256 user1Tokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Verify user1 got all-time high exemption (timestamp = type(uint).max)
        uint256 user1Timestamp = penaltyHook.getBuyerTimestamp(user1);
        assertEq(user1Timestamp, type(uint).max, "First buyer should get all-time high exemption");
        
        // Verify user1 has zero penalty
        uint256 user1Penalty = penaltyHook.calculatePenaltyFee(user1);
        assertEq(user1Penalty, 0, "All-time high buyer should have zero penalty");
        
        // User1 sells only half to keep some liquidity and avoid division by zero
        vm.prank(user1);
        b3.removeLiquidity(user1Tokens / 2, 0);
        
        // Now test user buys a smaller amount that doesn't reach the remaining all-time high
        vm.prank(testUser);
        bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT / 4, 0); // Smaller amount to avoid all-time high
        
        // Verify test user got normal timestamp (not type(uint).max)
        uint256 testUserTimestamp = penaltyHook.getBuyerTimestamp(testUser);
        assertLt(testUserTimestamp, type(uint).max, "Non-all-time-high buyer should get normal timestamp");
        assertGt(testUserTimestamp, 0, "Buyer should have non-zero timestamp");
        
        return bondingTokens;
    }

    // ============ TIMESTAMP TRACKING TESTS ============
    
    function test_BuyerTimestampRecordedOnPurchase() public {
        // Setup non-all-time-high scenario to get normal timestamp behavior
        _setupNonAllTimeHighScenario(user2);
        
        // Test user2 should have a normal timestamp recorded
        uint256 recordedTimestamp = penaltyHook.getBuyerTimestamp(user2);
        
        assertGt(recordedTimestamp, 0, "Timestamp should be recorded for buyer");
        assertLt(recordedTimestamp, type(uint).max, "Timestamp should not be all-time high exemption");
    }
    
    function test_TimestampUpdatedOnSubsequentBuy() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // First user establishes all-time high but only sells half
        vm.prank(user1);
        uint256 user1Tokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        vm.prank(user1);
        b3.removeLiquidity(user1Tokens / 2, 0); // Only sell half
        
        // User2 first buy at lower price
        vm.prank(user2);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT / 8, 0); // Small amount
        uint256 firstTimestamp = penaltyHook.getBuyerTimestamp(user2);
        
        // Wait some time and buy again with smaller amount
        vm.warp(block.timestamp + ONE_HOUR);
        
        vm.prank(user2);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT / 16, 0); // Even smaller amount to avoid all-time high
        uint256 secondTimestamp = penaltyHook.getBuyerTimestamp(user2);
        
        assertGt(secondTimestamp, firstTimestamp, "Timestamp should be updated on subsequent buy");
        assertLt(secondTimestamp, type(uint).max, "Second buy should not trigger all-time high exemption");
    }
    
    function test_DifferentBuyersHaveDifferentTimestamps() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // User1 buys first (gets all-time high exemption)
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        uint256 timestamp1 = penaltyHook.getBuyerTimestamp(user1);
        
        // User1 sells to lower price
        uint256 user1Tokens = bondingToken.balanceOf(user1);
        vm.prank(user1);
        b3.removeLiquidity(user1Tokens, 0);
        
        // Wait and then user2 buys at lower price (not all-time high)
        vm.warp(block.timestamp + ONE_HOUR);
        
        vm.prank(user2);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        uint256 timestamp2 = penaltyHook.getBuyerTimestamp(user2);
        
        // User1 should have all-time high exemption, user2 should have normal timestamp
        assertEq(timestamp1, type(uint).max, "First buyer should get all-time high exemption");
        assertLt(timestamp2, type(uint).max, "Second buyer should have normal timestamp");
        assertGt(timestamp2, 0, "Second buyer should have valid timestamp");
    }
    
    function test_FirstTimeBuyerHasZeroTimestamp() public {
        uint256 timestamp = penaltyHook.getBuyerTimestamp(user1);
        assertEq(timestamp, 0, "First-time buyer should have zero timestamp");
    }

    // ============ FEE CALCULATION TESTS ============
    
    function test_ImmediateSellHasMaximumPenalty() public {
        // Setup non-all-time-high scenario
        uint256 bondingTokens = _setupNonAllTimeHighScenario(user2);
        
        uint256 baseOutputWithoutHook = b3.quoteRemoveLiquidity(bondingTokens);
        
        // Immediately sell (should get 100% penalty)
        vm.prank(user2);
        uint256 actualOutput = b3.removeLiquidity(bondingTokens, 0);
        
        // With 100% penalty, effective bonding tokens used should be 0, so output should be minimal
        assertLt(actualOutput, baseOutputWithoutHook, "Should receive less due to penalty");
        
        // Check penalty calculation directly
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user2);
        assertEq(penaltyFee, 1000, "Immediate sell should have maximum penalty (100%)");
    }
    
    function test_PenaltyDeclinesOverTime() public {
        // Setup non-all-time-high scenario
        _setupNonAllTimeHighScenario(user2);
        
        // Wait 10 hours and check penalty (should have 90% penalty)
        vm.warp(block.timestamp + (10 * ONE_HOUR));
        
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user2);
        assertEq(penaltyFee, 900, "10-hour wait should result in 90% penalty");
        
        // Wait another 10 hours (20 hours total, should have 80% penalty)
        vm.warp(block.timestamp + (10 * ONE_HOUR));
        
        uint256 penaltyFee2 = penaltyHook.calculatePenaltyFee(user2);
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
        
        // Setup non-all-time-high scenario with custom parameters
        _setupNonAllTimeHighScenario(user2);
        
        // Wait 5 hours and check penalty (should have 90% penalty with 2% decline rate)
        vm.warp(block.timestamp + (5 * ONE_HOUR));
        
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user2);
        assertEq(penaltyFee, 900, "Custom 2% rate should result in 90% penalty after 5 hours");
        
        // Wait until penalty should be zero (50 hours = 100% decline at 2% per hour)
        vm.warp(block.timestamp + (45 * ONE_HOUR)); // Total 50 hours
        
        uint256 penaltyFeeZero = penaltyHook.calculatePenaltyFee(user2);
        assertEq(penaltyFeeZero, 0, "Penalty should be zero after max duration");
    }

    // ============ INTEGRATION TESTS ============
    
    function test_PenaltyHookIntegratesWithBehodler3() public {
        // Setup non-all-time-high scenario
        uint256 bondingTokens = _setupNonAllTimeHighScenario(user2);
        
        // Verify hook is set
        assertEq(address(b3.getHook()), address(penaltyHook), "Hook should be set");
        
        // Verify timestamp was recorded
        uint256 timestamp = penaltyHook.getBuyerTimestamp(user2);
        assertGt(timestamp, 0, "Timestamp should be recorded");
        assertLt(timestamp, type(uint).max, "Should not be all-time high exemption");
        
        // Sell tokens immediately and verify penalty is applied
        uint256 baseOutput = b3.quoteRemoveLiquidity(bondingTokens);
        
        vm.prank(user2);
        uint256 actualOutput = b3.removeLiquidity(bondingTokens, 0);
        
        assertLt(actualOutput, baseOutput, "Should receive less due to penalty");
    }
    
    function test_MultipleBuysSingleSell() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(penaltyHook)));
        
        // First user establishes all-time high but only sells half
        vm.prank(user1);
        uint256 user1Tokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        vm.prank(user1);
        b3.removeLiquidity(user1Tokens / 2, 0); // Only sell half
        
        // User2 first buy at lower price
        vm.prank(user2);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT / 8, 0); // Small amount
        uint256 firstTimestamp = penaltyHook.getBuyerTimestamp(user2);
        
        // Wait and second buy (should reset timestamp)
        vm.warp(block.timestamp + (5 * ONE_HOUR));
        
        vm.prank(user2);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT / 16, 0); // Even smaller amount to avoid all-time high
        uint256 secondTimestamp = penaltyHook.getBuyerTimestamp(user2);
        
        assertGt(secondTimestamp, firstTimestamp, "Timestamp should be updated on second buy");
        assertLt(secondTimestamp, type(uint).max, "Second buy should not trigger all-time high exemption");
        
        // Immediately sell (penalty should be based on second buy)
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user2);
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
        // Setup non-all-time-high scenario
        _setupNonAllTimeHighScenario(user2);
        
        // Wait exactly 1 hour
        vm.warp(block.timestamp + ONE_HOUR);
        
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user2);
        assertEq(penaltyFee, 990, "Exactly 1 hour should result in 99% penalty");
        
        // Wait exactly 100 hours
        vm.warp(block.timestamp + (99 * ONE_HOUR)); // Total 100 hours
        
        uint256 penaltyFeeAtMax = penaltyHook.calculatePenaltyFee(user2);
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
        
        // First buyer will get all-time high exemption
        vm.expectEmit(true, false, false, true);
        emit BuyerTimestampRecorded(user1, type(uint).max);
        
        vm.prank(user1);
        uint256 user1Tokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Sell to lower price
        vm.prank(user1);
        b3.removeLiquidity(user1Tokens, 0);
        
        // Second buyer gets normal timestamp
        vm.expectEmit(true, false, false, false); // Don't check timestamp value since it's block.timestamp
        emit BuyerTimestampRecorded(user2, 0); // Placeholder value, actual event will have block.timestamp
        
        vm.prank(user2);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
    }
    
    function test_PenaltyAppliedEventEmitted() public {
        // Setup non-all-time-high scenario
        uint256 bondingTokens = _setupNonAllTimeHighScenario(user2);
        
        // Wait 2 hours
        vm.warp(block.timestamp + (2 * ONE_HOUR));
        
        vm.expectEmit(true, false, false, true);
        emit PenaltyApplied(user2, 980, 2);
        
        vm.prank(user2);
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
        // Record balance before any operations
        uint256 initialBalance = inputToken.balanceOf(user2);
        
        // Setup non-all-time-high scenario
        uint256 bondingTokens = _setupNonAllTimeHighScenario(user2);
        
        // Record balance after setup (to know how much was spent)
        uint256 balanceAfterBuy = inputToken.balanceOf(user2);
        uint256 inputSpent = initialBalance - balanceAfterBuy;
        
        // Wait 25 hours (should have 75% penalty)
        vm.warp(block.timestamp + (25 * ONE_HOUR));
        
        // Sell tokens
        vm.prank(user2);
        uint256 outputReceived = b3.removeLiquidity(bondingTokens, 0);
        
        uint256 finalBalance = inputToken.balanceOf(user2);
        uint256 totalReceived = finalBalance - balanceAfterBuy;
        
        assertEq(totalReceived, outputReceived, "Balance should reflect output received");
        assertLt(totalReceived, inputSpent, "Should receive less than input due to penalty");
        
        // Verify penalty was 75%
        uint256 penaltyFee = penaltyHook.calculatePenaltyFee(user2);
        assertEq(penaltyFee, 750, "25-hour wait should result in 75% penalty");
    }

    // ============ EVENT DEFINITIONS FOR COMPILATION ============
    
    event BuyerTimestampRecorded(address indexed buyer, uint256 timestamp);
    event PenaltyApplied(address indexed seller, uint256 penaltyFee, uint256 hoursElapsed);
    event PenaltyParametersUpdated(uint256 declineRatePerHour, uint256 maxDurationHours);
    event PenaltyStatusChanged(bool active);
}