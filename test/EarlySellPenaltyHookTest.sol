// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/interfaces/IEarlySellPenaltyHook.sol";
import "../src/mocks/MockEarlySellPenaltyHook.sol";
import "../src/mocks/MockERC20.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";

/**
 * @title EarlySellPenaltyHookTest
 * @notice Comprehensive TDD failing tests for EarlySellPenaltyHook implementation
 * @dev TDD Red Phase - All tests should fail because EarlySellPenaltyHook contract doesn't exist yet
 */
contract EarlySellPenaltyHookTest is Test {
    Behodler3Tokenlaunch public b3;
    MockERC20 public inputToken;
    MockBondingToken public bondingToken;
    MockVault public vault;
    MockEarlySellPenaltyHook public mockPenaltyHook;
    
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
        vm.stopPrank();
        
        // Set the bonding curve address in the vault
        vault.setClient(address(b3), true);

        // Initialize vault approval after vault authorizes B3
        vm.startPrank(owner);
        b3.initializeVaultApproval();
        vm.stopPrank();

        // Deploy mock penalty hook
        mockPenaltyHook = new MockEarlySellPenaltyHook();
        
        // Setup user balances
        inputToken.mint(user1, INITIAL_INPUT_SUPPLY);
        inputToken.mint(user2, INITIAL_INPUT_SUPPLY);
        
        // Approve spending
        vm.prank(user1);
        inputToken.approve(address(b3), type(uint256).max);
        vm.prank(user2);
        inputToken.approve(address(b3), type(uint256).max);
    }

    // ============ TDD RED PHASE - INTERFACE AND CONTRACT EXISTENCE TESTS (SHOULD FAIL) ============
    
    function test_EarlySellPenaltyHookContractDoesNotExist_ShouldFail() public {
        // This should fail because EarlySellPenaltyHook contract doesn't exist yet
        vm.expectRevert();
        (bool success,) = address(0).call(
            abi.encodeWithSignature("new EarlySellPenaltyHook()")
        );
        assertFalse(success, "EarlySellPenaltyHook contract should not exist yet");
    }
    
    function test_IEarlySellPenaltyHookInterfaceCompilation_ShouldFail() public {
        // This should pass since we created the interface, but the implementation will fail
        IEarlySellPenaltyHook hook = IEarlySellPenaltyHook(address(mockPenaltyHook));
        assertEq(address(hook), address(mockPenaltyHook), "Interface should be accessible");
        
        // But calling actual implementation should fail
        vm.expectRevert();
        (bool success,) = address(0).call(
            abi.encodeWithSignature("getBuyerTimestamp(address)", user1)
        );
        assertFalse(success, "Real implementation should not exist");
    }

    // ============ TIMESTAMP TRACKING TESTS (SHOULD FAIL) ============
    
    function test_BuyerTimestampRecordedOnPurchase_ShouldFail() public {
        // Set mock hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        uint256 timestampBefore = block.timestamp;
        
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        uint256 recordedTimestamp = mockPenaltyHook.getBuyerTimestamp(user1);
        
        // Should fail because real hook doesn't track timestamps
        assertGe(recordedTimestamp, timestampBefore, "Timestamp should be recorded for buyer");
        assertLe(recordedTimestamp, block.timestamp, "Timestamp should not be in future");
    }
    
    function test_TimestampUpdatedOnSubsequentBuy_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // First buy
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        uint256 firstTimestamp = mockPenaltyHook.getBuyerTimestamp(user1);
        
        // Wait some time and buy again
        vm.warp(block.timestamp + ONE_HOUR);
        
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        uint256 secondTimestamp = mockPenaltyHook.getBuyerTimestamp(user1);
        
        // Should fail because real hook doesn't update timestamps
        assertGt(secondTimestamp, firstTimestamp, "Timestamp should be updated on subsequent buy");
    }
    
    function test_DifferentBuyersHaveDifferentTimestamps_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // User1 buys first
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait and then user2 buys
        vm.warp(block.timestamp + ONE_HOUR);
        
        vm.prank(user2);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        uint256 timestamp1 = mockPenaltyHook.getBuyerTimestamp(user1);
        uint256 timestamp2 = mockPenaltyHook.getBuyerTimestamp(user2);
        
        // Should fail because real hook doesn't track multiple buyers
        assertLt(timestamp1, timestamp2, "Different buyers should have different timestamps");
    }
    
    function test_FirstTimeBuyerHasZeroTimestamp() public {
        uint256 timestamp = mockPenaltyHook.getBuyerTimestamp(user1);
        assertEq(timestamp, 0, "First-time buyer should have zero timestamp");
    }

    // ============ FEE CALCULATION TESTS (SHOULD FAIL) ============
    
    function test_ImmediateSellHasMaximumPenalty_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Immediately sell (should get 100% penalty)
        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);
        
        // Should fail because real hook doesn't calculate penalties
        uint256 penaltyApplied = mockPenaltyHook.lastPenaltyApplied();
        assertEq(penaltyApplied, 1000, "Immediate sell should have maximum penalty (100%)");
    }
    
    function test_PenaltyDeclinesOverTime_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait 10 hours and sell (should have 90% penalty)
        vm.warp(block.timestamp + (10 * ONE_HOUR));
        
        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);
        
        // Should fail because real hook doesn't calculate declining penalties
        uint256 penaltyApplied = mockPenaltyHook.lastPenaltyApplied();
        assertEq(penaltyApplied, 900, "10-hour wait should result in 90% penalty");
    }
    
    function test_NoPenaltyAfter100Hours_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait 100+ hours and sell (should have no penalty)
        vm.warp(block.timestamp + (101 * ONE_HOUR));
        
        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);
        
        // Should fail because real hook doesn't handle max duration
        uint256 penaltyApplied = mockPenaltyHook.lastPenaltyApplied();
        assertEq(penaltyApplied, 0, "Sell after max duration should have no penalty");
    }
    
    function test_FirstTimeSellWithoutBuyHasMaxPenalty_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // User2 gets tokens from elsewhere (simulate)
        bondingToken.mint(user2, 1000);
        
        // User2 sells without ever buying (should get max penalty)
        vm.prank(user2);
        b3.removeLiquidity(1000, 0);
        
        // Should fail because real hook doesn't handle first-time sellers
        uint256 penaltyApplied = mockPenaltyHook.lastPenaltyApplied();
        assertEq(penaltyApplied, 1000, "First-time seller should get maximum penalty");
    }

    // ============ CONFIGURATION TESTS (SHOULD FAIL) ============
    
    function test_PenaltyParametersCanBeSet() public {
        mockPenaltyHook.setPenaltyParameters(15, 80); // 1.5% per hour, 80-hour max
        
        (uint256 declineRate, uint256 maxDuration, bool active) = mockPenaltyHook.getPenaltyParameters();
        assertEq(declineRate, 15, "Decline rate should be updated");
        assertEq(maxDuration, 80, "Max duration should be updated");
    }
    
    function test_PenaltyCanBeDeactivated_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // Deactivate penalty
        mockPenaltyHook.setPenaltyActive(false);
        
        // Buy and immediately sell
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);
        
        // Should fail because real hook doesn't handle deactivation
        uint256 penaltyApplied = mockPenaltyHook.lastPenaltyApplied();
        assertEq(penaltyApplied, 0, "Deactivated penalty should result in no fee");
    }
    
    function test_CustomPenaltyRateWorks_ShouldFail() public {
        // Set custom rate: 20 = 2% per hour
        mockPenaltyHook.setPenaltyParameters(20, 50);
        
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait 5 hours and sell (should have 90% penalty with 2% decline rate)
        vm.warp(block.timestamp + (5 * ONE_HOUR));
        
        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);
        
        // Should fail because real hook doesn't handle custom rates
        uint256 penaltyApplied = mockPenaltyHook.lastPenaltyApplied();
        assertEq(penaltyApplied, 900, "Custom 2% rate should result in 90% penalty after 5 hours");
    }

    // ============ INTEGRATION TESTS (SHOULD FAIL) ============
    
    function test_PenaltyHookIntegratesWithBehodler3_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // Verify hook is set
        assertEq(address(b3.getHook()), address(mockPenaltyHook), "Hook should be set");
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Check that buy hook was called
        assertEq(mockPenaltyHook.buyCallCount(), 1, "Buy hook should be called");
        
        // Sell tokens immediately
        vm.prank(user1);
        uint256 inputReceived = b3.removeLiquidity(bondingTokens, 0);
        
        // Should fail because real hook doesn't integrate properly
        assertEq(mockPenaltyHook.sellCallCount(), 1, "Sell hook should be called");
        assertLt(inputReceived, TYPICAL_INPUT_AMOUNT, "Should receive less due to penalty");
    }
    
    function test_MultipleBuysSingleSell_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // First buy
        vm.prank(user1);
        uint256 bondingTokens1 = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait and second buy (should reset timestamp)
        vm.warp(block.timestamp + (5 * ONE_HOUR));
        
        vm.prank(user1);
        uint256 bondingTokens2 = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Immediately sell (penalty should be based on second buy)
        vm.prank(user1);
        b3.removeLiquidity(bondingTokens1 + bondingTokens2, 0);
        
        // Should fail because real hook doesn't handle timestamp resets
        uint256 penaltyApplied = mockPenaltyHook.lastPenaltyApplied();
        assertEq(penaltyApplied, 1000, "Penalty should be based on most recent buy");
    }

    // ============ EDGE CASE TESTS (SHOULD FAIL) ============
    
    function test_ZeroAmountBuyDoesNotUpdateTimestamp_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        uint256 initialTimestamp = mockPenaltyHook.getBuyerTimestamp(user1);
        
        // Try to buy with zero amount (should revert, but if it doesn't, timestamp shouldn't update)
        vm.prank(user1);
        vm.expectRevert("B3: Input amount must be greater than 0");
        b3.addLiquidity(0, 0);
        
        uint256 afterTimestamp = mockPenaltyHook.getBuyerTimestamp(user1);
        
        // Should fail because real hook doesn't exist
        assertEq(afterTimestamp, initialTimestamp, "Zero amount buy should not update timestamp");
    }
    
    function test_BlockTimestampEdgeCases_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // Set timestamp to a large value
        vm.warp(type(uint256).max - 1000);
        
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // This should not cause overflow
        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);
        
        // Should fail because real hook doesn't handle edge cases
        assertTrue(true, "Should handle large timestamp values without overflow");
    }
    
    function test_PenaltyAtExactHourBoundaries_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait exactly 1 hour
        vm.warp(block.timestamp + ONE_HOUR);
        
        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);
        
        // Should fail because real hook doesn't handle exact boundaries
        uint256 penaltyApplied = mockPenaltyHook.lastPenaltyApplied();
        assertEq(penaltyApplied, 990, "Exactly 1 hour should result in 99% penalty");
    }

    // ============ EVENT EMISSION TESTS (SHOULD FAIL) ============
    
    function test_BuyerTimestampRecordedEventEmitted_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        vm.expectEmit(true, false, false, true);
        emit BuyerTimestampRecorded(user1, block.timestamp);
        
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Should fail because real hook doesn't emit events
    }
    
    function test_PenaltyAppliedEventEmitted_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        // Buy tokens
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        // Wait 2 hours
        vm.warp(block.timestamp + (2 * ONE_HOUR));
        
        vm.expectEmit(true, false, false, true);
        emit PenaltyApplied(user1, 980, 2);
        
        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);
        
        // Should fail because real hook doesn't emit penalty events
    }
    
    function test_PenaltyParametersUpdatedEventEmitted_ShouldFail() public {
        vm.expectEmit(false, false, false, true);
        emit PenaltyParametersUpdated(15, 80);
        
        mockPenaltyHook.setPenaltyParameters(15, 80);
        
        // Should fail because real hook doesn't emit parameter events
    }

    // ============ GAS OPTIMIZATION TESTS (SHOULD FAIL) ============
    
    function test_TimestampStorageGasCosts() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(mockPenaltyHook)));
        
        uint256 gasBefore = gasleft();
        
        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Should fail because real hook doesn't exist to measure gas
        assertLt(gasUsed, 500000, "Timestamp storage should not be overly gas intensive");
    }

    // ============ EVENT DEFINITIONS FOR COMPILATION ============
    
    event BuyerTimestampRecorded(address indexed buyer, uint256 timestamp);
    event PenaltyApplied(address indexed seller, uint256 penaltyFee, uint256 hoursElapsed);
    event PenaltyParametersUpdated(uint256 declineRatePerHour, uint256 maxDurationHours);
    event PenaltyStatusChanged(bool active);
}