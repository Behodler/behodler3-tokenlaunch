// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IBondingCurveHook
 * @notice Interface for buy and sell hooks in Behodler3Tokenlaunch
 * @dev Hooks are called during add liquidity (buy) and remove liquidity (sell) operations
 *      to allow custom fee structures and bonding token adjustments
 */
interface IBondingCurveHook {
    /**
     * @notice Hook called during add liquidity operations (buy)
     * @dev Called after base bonding token calculation but before final minting
     * @param buyer Address of the user adding liquidity
     * @param baseBondingToken Base amount of bonding tokens calculated before hook
     * @param baseInputToken Amount of input tokens being added to liquidity
     * @return fee Fee to be applied (0-1000 where 1000 = 100%, 5 = 0.5%)
     * @return deltaBondingToken Adjustment to bonding token amount (can be positive or negative)
     */
    function buy(
        address buyer,
        uint baseBondingToken,
        uint baseInputToken
    )
        external
        returns (uint fee, int deltaBondingToken);

    /**
     * @notice Hook called during remove liquidity operations (sell)
     * @dev Called after base input token calculation but before final transfer
     * @param seller Address of the user removing liquidity
     * @param baseBondingToken Amount of bonding tokens being burned
     * @param baseInputToken Base amount of input tokens calculated before hook
     * @return fee Fee to be applied (0-1000 where 1000 = 100%, 5 = 0.5%)
     * @return deltaBondingToken Adjustment to required bonding tokens (can be positive or negative)
     */
    function sell(
        address seller,
        uint baseBondingToken,
        uint baseInputToken
    )
        external
        returns (uint fee, int deltaBondingToken);
}
