// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IBondingToken
 * @notice Interface for the bonding token that represents liquidity in the B3 AMM
 */
interface IBondingToken is IERC20 {
    /**
     * @notice Mint bonding tokens to a recipient
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint amount) external;

    /**
     * @notice Burn bonding tokens from an address
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint amount) external;
}
