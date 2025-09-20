// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title ScribbleValidationContract
 * @notice Minimal contract with Scribble annotations to validate installation and configuration
 * @dev This contract demonstrates proper Scribble annotation usage for the TokenLaunch project
 */
/// #invariant {:msg "Balance must equal or be less than total deposits"} balance <= totalDeposits;
/// #invariant {:msg "Total deposits must be non-negative"} totalDeposits >= 0;
/// #invariant {:msg "Balance must be non-negative"} balance >= 0;
contract ScribbleValidationContract {
    uint public balance;
    uint public totalDeposits;
    mapping(address => uint) public userDeposits;

    event Deposit(address indexed user, uint amount);
    event Withdraw(address indexed user, uint amount);

    /// #if_succeeds {:msg "Balance must increase by amount"} balance == old(balance) + amount;
    /// #if_succeeds {:msg "Total deposits must increase by amount"} totalDeposits == old(totalDeposits) + amount;
    /// #if_succeeds {:msg "User deposit must increase by amount"} userDeposits[msg.sender] ==
    /// old(userDeposits[msg.sender]) + amount;
    function deposit(uint amount) external {
        require(amount > 0, "Amount must be positive");

        balance += amount;
        totalDeposits += amount;
        userDeposits[msg.sender] += amount;

        emit Deposit(msg.sender, amount);
    }

    /// #if_succeeds {:msg "Balance must decrease by amount"} balance == old(balance) - amount;
    /// #if_succeeds {:msg "User deposit must decrease by amount"} userDeposits[msg.sender] ==
    /// old(userDeposits[msg.sender]) - amount;
    function withdraw(uint amount) external {
        require(amount > 0, "Amount must be positive");
        require(userDeposits[msg.sender] >= amount, "Insufficient user balance");
        require(balance >= amount, "Insufficient contract balance");

        balance -= amount;
        userDeposits[msg.sender] -= amount;

        emit Withdraw(msg.sender, amount);
    }

    function getBalance() external view returns (uint) {
        return balance;
    }

    function getUserDeposit(address user) external view returns (uint) {
        return userDeposits[user];
    }
}
