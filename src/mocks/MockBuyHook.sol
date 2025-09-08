// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../interfaces/IBondingCurveHook.sol";

/**
 * @title MockBuyHook
 * @notice Mock hook contract for testing buy operations
 * @dev Allows configuration of return values for testing different scenarios
 */
contract MockBuyHook is IBondingCurveHook {
    uint256 public buyFee;
    int256 public buyDeltaBondingToken;
    uint256 public sellFee;
    int256 public sellDeltaBondingToken;
    
    // Call tracking
    uint256 public buyCallCount;
    uint256 public sellCallCount;
    address public lastBuyer;
    address public lastSeller;
    uint256 public lastBaseBondingToken;
    uint256 public lastBaseInputToken;
    
    constructor(
        uint256 _buyFee,
        int256 _buyDeltaBondingToken,
        uint256 _sellFee,
        int256 _sellDeltaBondingToken
    ) {
        buyFee = _buyFee;
        buyDeltaBondingToken = _buyDeltaBondingToken;
        sellFee = _sellFee;
        sellDeltaBondingToken = _sellDeltaBondingToken;
    }
    
    function buy(
        address buyer, 
        uint256 baseBondingToken, 
        uint256 baseInputToken
    ) external override returns (uint256 fee, int256 deltaBondingToken) {
        buyCallCount++;
        lastBuyer = buyer;
        lastBaseBondingToken = baseBondingToken;
        lastBaseInputToken = baseInputToken;
        
        return (buyFee, buyDeltaBondingToken);
    }
    
    function sell(
        address seller, 
        uint256 baseBondingToken, 
        uint256 baseInputToken
    ) external override returns (uint256 fee, int256 deltaBondingToken) {
        sellCallCount++;
        lastSeller = seller;
        lastBaseBondingToken = baseBondingToken;
        lastBaseInputToken = baseInputToken;
        
        return (sellFee, sellDeltaBondingToken);
    }
    
    // Configuration functions
    function setBuyParams(uint256 _fee, int256 _deltaBondingToken) external {
        buyFee = _fee;
        buyDeltaBondingToken = _deltaBondingToken;
    }
    
    function setSellParams(uint256 _fee, int256 _deltaBondingToken) external {
        sellFee = _fee;
        sellDeltaBondingToken = _deltaBondingToken;
    }
    
    function resetCallCounts() external {
        buyCallCount = 0;
        sellCallCount = 0;
    }
}