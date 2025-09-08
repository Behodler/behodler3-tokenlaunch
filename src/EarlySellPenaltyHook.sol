// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IEarlySellPenaltyHook.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EarlySellPenaltyHook
 * @notice Hook that applies time-based penalties to discourage early selling after token purchases
 * @dev Tracks buyer timestamps and applies declining sell fees based on time elapsed since the last buy transaction
 */
contract EarlySellPenaltyHook is IEarlySellPenaltyHook, Ownable {
    
    // ============ STATE VARIABLES ============
    
    /// @notice Mapping of buyer addresses to their last buy timestamps
    mapping(address => uint256) private buyerLastBuyTimestamp;
    
    /// @notice Rate at which penalty declines per hour (1% = 10 in fee units)
    uint256 public penaltyDeclineRatePerHour = 10;
    
    /// @notice Maximum duration in hours after which penalty is 0
    uint256 public maxPenaltyDurationHours = 100;
    
    /// @notice Whether penalty mechanism is currently active
    bool public penaltyActive = true;
    
    // ============ CONSTRUCTOR ============
    
    constructor() Ownable(msg.sender) {}
    
    // ============ HOOK IMPLEMENTATION ============
    
    /**
     * @notice Hook called during buy operations - records/updates buyer timestamps
     * @param buyer Address of the user buying tokens
     * @param baseBondingToken Base amount of bonding tokens calculated before hook
     * @param baseInputToken Amount of input tokens being added to liquidity
     * @return fee Fee to be applied (always 0 for buy operations)
     * @return deltaBondingToken Adjustment to bonding token amount (always 0)
     */
    function buy(
        address buyer, 
        uint256 baseBondingToken, 
        uint256 baseInputToken
    ) external override returns (uint256 fee, int256 deltaBondingToken) {
        // Record timestamp for buyer (updates existing timestamp if buyer already exists)
        buyerLastBuyTimestamp[buyer] = block.timestamp;
        
        emit BuyerTimestampRecorded(buyer, block.timestamp);
        
        // No fee or adjustment for buy operations
        return (0, 0);
    }
    
    /**
     * @notice Hook called during sell operations - calculates and applies time-based penalty
     * @param seller Address of the user selling tokens
     * @param baseBondingToken Amount of bonding tokens being burned
     * @param baseInputToken Base amount of input tokens calculated before hook
     * @return fee Time-based penalty fee (0-1000 where 1000 = 100%)
     * @return deltaBondingToken Adjustment to bonding token amount (always 0)
     */
    function sell(
        address seller, 
        uint256 baseBondingToken, 
        uint256 baseInputToken
    ) external override returns (uint256 fee, int256 deltaBondingToken) {
        if (!penaltyActive) {
            return (0, 0);
        }
        
        uint256 penaltyFee = calculatePenaltyFee(seller);
        
        if (penaltyFee > 0) {
            uint256 hoursElapsed = _getHoursElapsed(seller);
            emit PenaltyApplied(seller, penaltyFee, hoursElapsed);
        }
        
        // Return penalty as fee, no bonding token adjustment
        return (penaltyFee, 0);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /**
     * @notice Get the timestamp of a buyer's last purchase
     * @param buyer Address of the buyer to query
     * @return timestamp Last buy timestamp for the buyer (0 if never bought)
     */
    function getBuyerTimestamp(address buyer) external view override returns (uint256 timestamp) {
        return buyerLastBuyTimestamp[buyer];
    }
    
    /**
     * @notice Get current penalty parameters
     * @return declineRate Penalty decline rate per hour
     * @return maxDuration Maximum penalty duration in hours
     * @return active Whether penalty is currently active
     */
    function getPenaltyParameters() external view override returns (uint256 declineRate, uint256 maxDuration, bool active) {
        return (penaltyDeclineRatePerHour, maxPenaltyDurationHours, penaltyActive);
    }
    
    /**
     * @notice Calculate current penalty fee for a seller based on time elapsed
     * @param seller Address of the seller
     * @return penaltyFee Fee amount (0-1000 where 1000 = 100%)
     */
    function calculatePenaltyFee(address seller) public view override returns (uint256 penaltyFee) {
        if (!penaltyActive) {
            return 0;
        }
        
        uint256 lastBuyTimestamp = buyerLastBuyTimestamp[seller];
        
        // First-time seller without previous buy gets maximum penalty
        if (lastBuyTimestamp == 0) {
            return 1000;
        }
        
        uint256 hoursElapsed = _getHoursElapsed(seller);
        
        // No penalty after maximum duration
        if (hoursElapsed >= maxPenaltyDurationHours) {
            return 0;
        }
        
        // Calculate declining penalty: starts at 100% (1000), declines by penaltyDeclineRatePerHour per hour
        uint256 penalty = 1000 - (hoursElapsed * penaltyDeclineRatePerHour);
        
        // Ensure penalty doesn't underflow (though mathematically it shouldn't with proper maxDurationHours)
        return penalty > 1000 ? 0 : penalty;
    }
    
    // ============ OWNER FUNCTIONS ============
    
    /**
     * @notice Set penalty parameters (owner only)
     * @param _declineRatePerHour Rate at which penalty declines per hour (1% = 10 in fee units)
     * @param _maxDurationHours Maximum duration in hours after which penalty is 0
     */
    function setPenaltyParameters(uint256 _declineRatePerHour, uint256 _maxDurationHours) external override onlyOwner {
        require(_declineRatePerHour > 0, "EarlySellPenaltyHook: Decline rate must be greater than 0");
        require(_maxDurationHours > 0, "EarlySellPenaltyHook: Max duration must be greater than 0");
        require(_declineRatePerHour * _maxDurationHours >= 1000, "EarlySellPenaltyHook: Parameters must allow penalty to reach 0");
        
        penaltyDeclineRatePerHour = _declineRatePerHour;
        maxPenaltyDurationHours = _maxDurationHours;
        
        emit PenaltyParametersUpdated(_declineRatePerHour, _maxDurationHours);
    }
    
    /**
     * @notice Set whether penalty is active (owner only)
     * @param _active Whether penalty mechanism is active
     */
    function setPenaltyActive(bool _active) external override onlyOwner {
        penaltyActive = _active;
        emit PenaltyStatusChanged(_active);
    }
    
    // ============ INTERNAL HELPER FUNCTIONS ============
    
    /**
     * @notice Calculate hours elapsed since seller's last buy
     * @param seller Address of the seller
     * @return hoursElapsed Number of complete hours since last buy
     */
    function _getHoursElapsed(address seller) internal view returns (uint256 hoursElapsed) {
        uint256 lastBuyTimestamp = buyerLastBuyTimestamp[seller];
        
        if (lastBuyTimestamp == 0) {
            return 0;
        }
        
        // Handle edge case where block.timestamp might be less than lastBuyTimestamp (should never happen in practice)
        if (block.timestamp < lastBuyTimestamp) {
            return 0;
        }
        
        uint256 timeElapsed = block.timestamp - lastBuyTimestamp;
        return timeElapsed / 3600; // 3600 seconds = 1 hour
    }
}