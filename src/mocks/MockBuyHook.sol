// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../interfaces/IBondingCurveHook.sol";

/**
 * @title MockBuyHook
 * @notice Mock hook contract for testing buy operations
 * @dev Allows configuration of return values for testing different scenarios
 */
contract MockBuyHook is IBondingCurveHook {
    uint public buyFee;
    int public buyDeltaBondingToken;
    uint public sellFee;
    int public sellDeltaBondingToken;

    // Call tracking
    uint public buyCallCount;
    uint public sellCallCount;
    address public lastBuyer;
    address public lastSeller;
    uint public lastBaseBondingToken;
    uint public lastBaseInputToken;

    constructor(uint _buyFee, int _buyDeltaBondingToken, uint _sellFee, int _sellDeltaBondingToken) {
        buyFee = _buyFee;
        buyDeltaBondingToken = _buyDeltaBondingToken;
        sellFee = _sellFee;
        sellDeltaBondingToken = _sellDeltaBondingToken;
    }

    function buy(
        address buyer,
        uint baseBondingToken,
        uint baseInputToken
    )
        external
        override
        returns (uint fee, int deltaBondingToken)
    {
        buyCallCount++;
        lastBuyer = buyer;
        lastBaseBondingToken = baseBondingToken;
        lastBaseInputToken = baseInputToken;

        return (buyFee, buyDeltaBondingToken);
    }

    function sell(
        address seller,
        uint baseBondingToken,
        uint baseInputToken
    )
        external
        override
        returns (uint fee, int deltaBondingToken)
    {
        sellCallCount++;
        lastSeller = seller;
        lastBaseBondingToken = baseBondingToken;
        lastBaseInputToken = baseInputToken;

        return (sellFee, sellDeltaBondingToken);
    }

    // Configuration functions
    function setBuyParams(uint _fee, int _deltaBondingToken) external {
        buyFee = _fee;
        buyDeltaBondingToken = _deltaBondingToken;
    }

    function setSellParams(uint _fee, int _deltaBondingToken) external {
        sellFee = _fee;
        sellDeltaBondingToken = _deltaBondingToken;
    }

    function resetCallCounts() external {
        buyCallCount = 0;
        sellCallCount = 0;
    }
}
