// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IBondingCurveHook.sol";

/**
 * @title IEarlySellPenaltyHook
 * @notice Interface for early sell penalty hook that applies time-based penalties to discourage early selling
 * @dev Extends IBondingCurveHook with timestamp tracking and penalty configuration functions
 */
interface IEarlySellPenaltyHook is IBondingCurveHook {
    /**
     * @notice Get the timestamp of a buyer's last purchase
     * @param buyer Address of the buyer to query
     * @return timestamp Last buy timestamp for the buyer (0 if never bought)
     */
    function getBuyerTimestamp(address buyer) external view returns (uint256 timestamp);

    /**
     * @notice Set penalty parameters (owner only)
     * @param _declineRatePerHour Rate at which penalty declines per hour (1% = 10 in fee units)
     * @param _maxDurationHours Maximum duration in hours after which penalty is 0
     */
    function setPenaltyParameters(uint256 _declineRatePerHour, uint256 _maxDurationHours) external;

    /**
     * @notice Set whether penalty is active (owner only)
     * @param _active Whether penalty mechanism is active
     */
    function setPenaltyActive(bool _active) external;

    /**
     * @notice Get current penalty parameters
     * @return declineRate Penalty decline rate per hour
     * @return maxDuration Maximum penalty duration in hours
     * @return active Whether penalty is currently active
     */
    function getPenaltyParameters() external view returns (uint256 declineRate, uint256 maxDuration, bool active);

    /**
     * @notice Calculate current penalty fee for a seller based on time elapsed
     * @param seller Address of the seller
     * @return penaltyFee Fee amount (0-1000 where 1000 = 100%)
     */
    function calculatePenaltyFee(address seller) external view returns (uint256 penaltyFee);

    // Events
    event BuyerTimestampRecorded(address indexed buyer, uint256 timestamp);
    event PenaltyParametersUpdated(uint256 declineRatePerHour, uint256 maxDurationHours);
    event PenaltyStatusChanged(bool active);
    event PenaltyApplied(address indexed seller, uint256 penaltyFee, uint256 hoursElapsed);
}
