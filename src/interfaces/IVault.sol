// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IVault
 * @notice Interface for vault contract that handles token deposits and withdrawals
 */
interface IVault {
    /**
     * @notice Deposit tokens into the vault
     * @param token The token address to deposit
     * @param amount The amount of tokens to deposit
     * @param recipient The address that will own the deposited tokens
     */
    function deposit(address token, uint256 amount, address recipient) external;

    /**
     * @notice Withdraw tokens from the vault
     * @param token The token address to withdraw
     * @param amount The amount of tokens to withdraw
     * @param recipient The address that will receive the tokens
     */
    function withdraw(address token, uint256 amount, address recipient) external;

    /**
     * @notice Get the balance of a token for a specific address
     * @param token The token address
     * @param account The account address
     * @return The token balance
     */
    function balanceOf(address token, address account) external view returns (uint256);
}