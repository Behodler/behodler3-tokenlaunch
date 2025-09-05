// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../interfaces/IBondingToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockBondingToken
 * @notice Mock implementation of IBondingToken for testing purposes
 * @dev Simple ERC20 with mint and burn functionality, no access control for testing
 */
contract MockBondingToken is ERC20, IBondingToken {
    
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /**
     * @notice Mint bonding tokens to a recipient
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external override {
        require(to != address(0), "MockBondingToken: mint to zero address");
        require(amount > 0, "MockBondingToken: mint amount is zero");
        _mint(to, amount);
    }

    /**
     * @notice Burn bonding tokens from an address
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external override {
        require(from != address(0), "MockBondingToken: burn from zero address");
        require(amount > 0, "MockBondingToken: burn amount is zero");
        require(balanceOf(from) >= amount, "MockBondingToken: burn amount exceeds balance");
        _burn(from, amount);
    }

    // Additional helper functions for testing
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return super.totalSupply();
    }
}