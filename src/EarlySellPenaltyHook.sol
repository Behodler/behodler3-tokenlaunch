// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IEarlySellPenaltyHook.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EarlySellPenaltyHook
 * @notice Hook that applies time-based penalties to discourage early selling after token purchases
 * @dev Tracks buyer timestamps and applies declining sell fees based on time elapsed since the last buy transaction
 */
/// #invariant {:msg "Penalty decline rate must be positive if set"} penaltyDeclineRatePerHour == 0 ||
/// penaltyDeclineRatePerHour > 0;
/// #invariant {:msg "Max penalty duration must be positive if set"} maxPenaltyDurationHours == 0 ||
/// maxPenaltyDurationHours > 0;
/// #invariant {:msg "Penalty parameters must allow penalty to reach zero"} penaltyDeclineRatePerHour == 0 ||
/// maxPenaltyDurationHours == 0 || penaltyDeclineRatePerHour * maxPenaltyDurationHours >= 1000;
/// #invariant {:msg "Penalty active state must be consistent"} penaltyActive == true || penaltyActive == false;
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
    /// #if_succeeds {:msg "Buyer address must not be zero"} buyer != address(0);
    /// #if_succeeds {:msg "Buy operations never apply fees"} fee == 0;
    /// #if_succeeds {:msg "Buy operations never adjust bonding tokens"} deltaBondingToken == 0;
    /// #if_succeeds {:msg "Buyer timestamp should be updated to current block"} buyerLastBuyTimestamp[buyer] ==
    /// block.timestamp;
    function buy(address buyer, uint256 baseBondingToken, uint256 baseInputToken)
        external
        override
        returns (uint256 fee, int256 deltaBondingToken)
    {
        // TIMESTAMP STORAGE LOGIC:
        // Store the current block timestamp for the buyer. This timestamp serves as the
        // starting point for penalty calculations on future sell operations.
        // Key behaviors:
        // 1. First-time buyers: Creates new timestamp entry
        // 2. Existing buyers: RESETS timestamp to current block time
        // 3. Timestamp reset prevents gaming through multiple small buys
        // 4. Each buy operation starts a new penalty countdown based on maxPenaltyDurationHours

        buyerLastBuyTimestamp[buyer] = block.timestamp;

        emit BuyerTimestampRecorded(buyer, block.timestamp);

        // Buy operations never apply fees or adjust bonding token amounts
        // The penalty mechanism only applies to sell operations
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
    /// #if_succeeds {:msg "Seller address must not be zero"} seller != address(0);
    /// #if_succeeds {:msg "Fee must be within valid range"} fee <= 1000;
    /// #if_succeeds {:msg "Sell operations never adjust bonding tokens"} deltaBondingToken == 0;
    /// #if_succeeds {:msg "If penalty is inactive, fee should be zero"} !penaltyActive ==> fee == 0;
    /// #if_succeeds {:msg "If seller never bought, fee should be maximum when penalty active"} penaltyActive &&
    /// buyerLastBuyTimestamp[seller] == 0 ==> fee == 1000;
    function sell(address seller, uint256 baseBondingToken, uint256 baseInputToken)
        external
        override
        returns (uint256 fee, int256 deltaBondingToken)
    {
        // PENALTY ACTIVATION CHECK:
        // Allow owner to temporarily disable penalty mechanism for emergencies,
        // contract upgrades, or market interventions without needing to change the hook
        if (!penaltyActive) {
            return (0, 0);
        }

        // PENALTY CALCULATION:
        // Calculate the time-based penalty using the core penalty algorithm
        // This accounts for time elapsed, first-time seller checks, and parameter limits
        uint256 penaltyFee = calculatePenaltyFee(seller);

        // EVENT EMISSION FOR MONITORING:
        // Only emit penalty events when a penalty is actually applied
        // This helps with gas efficiency and event log clarity
        if (penaltyFee > 0) {
            uint256 hoursElapsed = _getHoursElapsed(seller);
            emit PenaltyApplied(seller, penaltyFee, hoursElapsed);
        }

        // RETURN VALUES:
        // fee: Penalty amount in basis points (0-1000)
        // deltaBondingToken: Always 0 - we don't adjust token amounts, only apply fees
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
    function getPenaltyParameters()
        external
        view
        override
        returns (uint256 declineRate, uint256 maxDuration, bool active)
    {
        return (penaltyDeclineRatePerHour, maxPenaltyDurationHours, penaltyActive);
    }

    /**
     * @notice Calculate current penalty fee for a seller based on time elapsed
     * @param seller Address of the seller
     * @return penaltyFee Fee amount (0-1000 where 1000 = 100%)
     */
    function calculatePenaltyFee(address seller) public view override returns (uint256 penaltyFee) {
        // EMERGENCY PAUSE CHECK:
        // If penalty is deactivated, return zero regardless of time elapsed
        if (!penaltyActive) {
            return 0;
        }

        uint256 lastBuyTimestamp = buyerLastBuyTimestamp[seller];

        // FIRST-TIME SELLER PROTECTION:
        // Users who never bought tokens (airdrop recipients, transfers, etc.)
        // receive maximum penalty to prevent gaming the system
        // This ensures the penalty mechanism applies to all sellers
        if (lastBuyTimestamp == 0) {
            return 1000; // 100% penalty
        }

        uint256 hoursElapsed = _getHoursElapsed(seller);

        // 96-HOUR WINDOW IMPLEMENTATION:
        // After the maximum penalty duration, no penalty is applied
        // This creates a clear "safe window" for selling without penalty
        if (hoursElapsed >= maxPenaltyDurationHours) {
            return 0;
        }

        // DECLINING PENALTY CALCULATION:
        // Implements linear decay: penalty = max(0, 100% - (hours × decline_rate))
        // Default: 100% - (hours × 1%) = penalty that reaches 0% at 100 hours
        // Formula ensures penalty declines predictably and reaches zero at max duration
        uint256 penalty = 1000 - (hoursElapsed * penaltyDeclineRatePerHour);

        // UNDERFLOW PROTECTION:
        // Mathematical safety check - with proper parameters this should never trigger
        // But included for defensive programming against potential parameter misconfigurations
        return penalty > 1000 ? 0 : penalty;
    }

    // ============ OWNER FUNCTIONS ============

    /**
     * @notice Set penalty parameters (owner only)
     * @param _declineRatePerHour Rate at which penalty declines per hour (1% = 10 in fee units)
     * @param _maxDurationHours Maximum duration in hours after which penalty is 0
     */
    /// #if_succeeds {:msg "Only owner can set penalty parameters"} msg.sender == owner();
    /// #if_succeeds {:msg "Decline rate must be positive"} _declineRatePerHour > 0;
    /// #if_succeeds {:msg "Max duration must be positive"} _maxDurationHours > 0;
    /// #if_succeeds {:msg "Parameters must allow penalty to reach zero"} _declineRatePerHour * _maxDurationHours >=
    /// 1000;
    /// #if_succeeds {:msg "Decline rate should be set correctly"} penaltyDeclineRatePerHour == _declineRatePerHour;
    /// #if_succeeds {:msg "Max duration should be set correctly"} maxPenaltyDurationHours == _maxDurationHours;
    function setPenaltyParameters(uint256 _declineRatePerHour, uint256 _maxDurationHours) external override onlyOwner {
        require(_declineRatePerHour > 0, "EarlySellPenaltyHook: Decline rate must be greater than 0");
        require(_maxDurationHours > 0, "EarlySellPenaltyHook: Max duration must be greater than 0");
        require(
            _declineRatePerHour * _maxDurationHours >= 1000,
            "EarlySellPenaltyHook: Parameters must allow penalty to reach 0"
        );

        penaltyDeclineRatePerHour = _declineRatePerHour;
        maxPenaltyDurationHours = _maxDurationHours;

        emit PenaltyParametersUpdated(_declineRatePerHour, _maxDurationHours);
    }

    /**
     * @notice Set whether penalty is active (owner only)
     * @param _active Whether penalty mechanism is active
     */
    /// #if_succeeds {:msg "Only owner can set penalty active status"} msg.sender == owner();
    /// #if_succeeds {:msg "Penalty active should be set to specified value"} penaltyActive == _active;
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

        // FIRST-TIME SELLER HANDLING:
        // If no timestamp exists, return 0 hours elapsed
        // This will be handled by the calling function (usually triggers max penalty)
        if (lastBuyTimestamp == 0) {
            return 0;
        }

        // TIME CONVERSION LOGIC:
        // Convert seconds elapsed to complete hours (truncates partial hours)
        // This creates clear hourly boundaries for penalty reductions
        // Example: 3599 seconds = 0 hours, 3600 seconds = 1 hour, 7199 seconds = 1 hour
        uint256 timeElapsed = block.timestamp - lastBuyTimestamp;
        return timeElapsed / 3600; // 3600 seconds = 1 hour
    }
}
