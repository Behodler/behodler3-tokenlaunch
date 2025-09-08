// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../interfaces/IBondingCurveHook.sol";

/**
 * @title MockZeroHook
 * @notice Mock hook contract that returns zero values for both fee and deltaBondingToken
 * @dev Used to test neutral hook behavior that doesn't affect calculations
 */
contract MockZeroHook is IBondingCurveHook {
    // Call tracking
    uint256 public buyCallCount;
    uint256 public sellCallCount;
    address public lastBuyer;
    address public lastSeller;
    uint256 public lastBaseBondingToken;
    uint256 public lastBaseInputToken;
    
    function buy(
        address buyer, 
        uint256 baseBondingToken, 
        uint256 baseInputToken
    ) external override returns (uint256 fee, int256 deltaBondingToken) {
        buyCallCount++;
        lastBuyer = buyer;
        lastBaseBondingToken = baseBondingToken;
        lastBaseInputToken = baseInputToken;
        
        return (0, 0);
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
        
        return (0, 0);
    }
    
    function resetCallCounts() external {
        buyCallCount = 0;
        sellCallCount = 0;
    }
}