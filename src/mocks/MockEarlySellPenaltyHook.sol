// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../interfaces/IEarlySellPenaltyHook.sol";

/**
 * @title MockEarlySellPenaltyHook
 * @notice Mock implementation of early sell penalty hook for testing
 * @dev Provides configurable behavior for testing different penalty scenarios
 */
contract MockEarlySellPenaltyHook is IEarlySellPenaltyHook {
    // Mock state variables
    mapping(address => uint256) private mockBuyerTimestamps;
    uint256 public penaltyDeclineRatePerHour = 10; // Default 1% per hour
    uint256 public maxPenaltyDurationHours = 100;
    bool public penaltyActive = true;

    // Call tracking for tests
    uint256 public buyCallCount;
    uint256 public sellCallCount;
    address public lastBuyer;
    address public lastSeller;
    uint256 public lastBaseBondingToken;
    uint256 public lastBaseInputToken;
    uint256 public lastPenaltyApplied;

    // Override behavior controls
    bool public shouldFailOnBuy;
    bool public shouldFailOnSell;
    uint256 public mockCurrentTime;
    bool public useRealBlockTimestamp = true;

    function buy(address buyer, uint256 baseBondingToken, uint256 baseInputToken)
        external
        override
        returns (uint256 fee, int256 deltaBondingToken)
    {
        if (shouldFailOnBuy) {
            revert("MockEarlySellPenaltyHook: Buy failed");
        }

        buyCallCount++;
        lastBuyer = buyer;
        lastBaseBondingToken = baseBondingToken;
        lastBaseInputToken = baseInputToken;

        // Record timestamp for buyer
        uint256 currentTime = useRealBlockTimestamp ? block.timestamp : mockCurrentTime;
        mockBuyerTimestamps[buyer] = currentTime;

        emit BuyerTimestampRecorded(buyer, currentTime);

        // Return no fee and no delta for buy operations
        return (0, 0);
    }

    function sell(address seller, uint256 baseBondingToken, uint256 baseInputToken)
        external
        override
        returns (uint256 fee, int256 deltaBondingToken)
    {
        if (shouldFailOnSell) {
            revert("MockEarlySellPenaltyHook: Sell failed");
        }

        sellCallCount++;
        lastSeller = seller;
        lastBaseBondingToken = baseBondingToken;
        lastBaseInputToken = baseInputToken;

        // Calculate penalty fee
        uint256 penaltyFee = calculatePenaltyFee(seller);
        lastPenaltyApplied = penaltyFee;

        if (penaltyFee > 0) {
            uint256 hoursElapsed = getHoursElapsed(seller);
            emit PenaltyApplied(seller, penaltyFee, hoursElapsed);
        }

        // Return penalty as fee, no delta adjustment
        return (penaltyFee, 0);
    }

    function getBuyerTimestamp(address buyer) external view override returns (uint256 timestamp) {
        return mockBuyerTimestamps[buyer];
    }

    function setPenaltyParameters(uint256 _declineRatePerHour, uint256 _maxDurationHours) external override {
        penaltyDeclineRatePerHour = _declineRatePerHour;
        maxPenaltyDurationHours = _maxDurationHours;
        emit PenaltyParametersUpdated(_declineRatePerHour, _maxDurationHours);
    }

    function setPenaltyActive(bool _active) external override {
        penaltyActive = _active;
        emit PenaltyStatusChanged(_active);
    }

    function getPenaltyParameters()
        external
        view
        override
        returns (uint256 declineRate, uint256 maxDuration, bool active)
    {
        return (penaltyDeclineRatePerHour, maxPenaltyDurationHours, penaltyActive);
    }

    function calculatePenaltyFee(address seller) public view override returns (uint256 penaltyFee) {
        if (!penaltyActive) return 0;

        uint256 lastBuyTimestamp = mockBuyerTimestamps[seller];
        if (lastBuyTimestamp == 0) {
            // First-time seller without previous buy gets maximum penalty
            return 1000;
        }

        uint256 currentTime = useRealBlockTimestamp ? block.timestamp : mockCurrentTime;
        uint256 timeElapsed = currentTime - lastBuyTimestamp;
        uint256 hoursElapsed = timeElapsed / 3600;

        if (hoursElapsed >= maxPenaltyDurationHours) {
            return 0;
        }

        // Calculate declining penalty: starts at 100% (1000), declines by penaltyDeclineRatePerHour per hour
        uint256 penalty = 1000 - (hoursElapsed * penaltyDeclineRatePerHour);

        // Ensure penalty doesn't go negative
        return penalty > 1000 ? 0 : penalty;
    }

    // Helper functions for testing
    function getHoursElapsed(address seller) public view returns (uint256) {
        uint256 lastBuyTimestamp = mockBuyerTimestamps[seller];
        if (lastBuyTimestamp == 0) return 0;

        uint256 currentTime = useRealBlockTimestamp ? block.timestamp : mockCurrentTime;
        return (currentTime - lastBuyTimestamp) / 3600;
    }

    function setMockTimestamp(uint256 timestamp) external {
        mockCurrentTime = timestamp;
        useRealBlockTimestamp = false;
    }

    function useRealTimestamp() external {
        useRealBlockTimestamp = true;
    }

    function setBuyerTimestamp(address buyer, uint256 timestamp) external {
        mockBuyerTimestamps[buyer] = timestamp;
    }

    function setFailureMode(bool _shouldFailOnBuy, bool _shouldFailOnSell) external {
        shouldFailOnBuy = _shouldFailOnBuy;
        shouldFailOnSell = _shouldFailOnSell;
    }

    function resetCallCounts() external {
        buyCallCount = 0;
        sellCallCount = 0;
        lastPenaltyApplied = 0;
    }
}
