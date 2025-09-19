// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../interfaces/IBondingCurveHook.sol";

/**
 * @title MockFailingHook
 * @notice Mock hook contract that reverts to test error handling
 * @dev Used to test how the system handles hook failures
 */
contract MockFailingHook is IBondingCurveHook {
    string public buyRevertMessage;
    string public sellRevertMessage;
    bool public shouldBuyFail;
    bool public shouldSellFail;

    // Call tracking
    uint public buyCallCount;
    uint public sellCallCount;

    constructor(
        bool _shouldBuyFail,
        bool _shouldSellFail,
        string memory _buyRevertMessage,
        string memory _sellRevertMessage
    ) {
        shouldBuyFail = _shouldBuyFail;
        shouldSellFail = _shouldSellFail;
        buyRevertMessage = _buyRevertMessage;
        sellRevertMessage = _sellRevertMessage;
    }

    function buy(address, uint, uint) external override returns (uint, int) {
        buyCallCount++;

        if (shouldBuyFail) {
            revert(buyRevertMessage);
        }

        return (0, 0);
    }

    function sell(address, uint, uint) external override returns (uint, int) {
        sellCallCount++;

        if (shouldSellFail) {
            revert(sellRevertMessage);
        }

        return (0, 0);
    }

    // Configuration functions
    function setFailureMode(bool _buyFail, bool _sellFail) external {
        shouldBuyFail = _buyFail;
        shouldSellFail = _sellFail;
    }

    function setRevertMessages(string memory _buyMessage, string memory _sellMessage) external {
        buyRevertMessage = _buyMessage;
        sellRevertMessage = _sellMessage;
    }

    function resetCallCounts() external {
        buyCallCount = 0;
        sellCallCount = 0;
    }
}
