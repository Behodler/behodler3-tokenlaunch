// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Vault
 * @notice Abstract vault contract with security features and access control
 * @dev Provides base implementation for vault contracts with owner and bonding curve access control
 */
abstract contract Vault is IVault, Ownable {
    
    // ============ STATE VARIABLES ============
    
    /// @notice The address of the bonding curve contract authorized to deposit/withdraw
    address public bondingCurve;
    
    // ============ EVENTS ============
    
    /**
     * @notice Emitted when the bonding curve address is updated
     * @param oldBondingCurve The previous bonding curve address
     * @param newBondingCurve The new bonding curve address
     */
    event BondingCurveSet(address indexed oldBondingCurve, address indexed newBondingCurve);
    
    /**
     * @notice Emitted when an emergency withdrawal is performed
     * @param owner The owner who performed the withdrawal
     * @param amount The amount withdrawn
     */
    event EmergencyWithdraw(address indexed owner, uint256 amount);
    
    // ============ MODIFIERS ============
    
    /**
     * @notice Restricts access to only the bonding curve contract
     * @dev Reverts if the caller is not the designated bonding curve address
     */
    modifier onlyBondingCurve() {
        require(msg.sender == bondingCurve, "Vault: unauthorized, only bonding curve");
        _;
    }
    
    // ============ CONSTRUCTOR ============
    
    /**
     * @notice Initialize the vault with initial owner
     * @param _owner The initial owner of the contract
     */
    constructor(address _owner) Ownable(_owner) {
        require(_owner != address(0), "Vault: owner cannot be zero address");
    }
    
    // ============ OWNER FUNCTIONS ============
    
    /**
     * @notice Set the bonding curve address that is authorized to call deposit/withdraw
     * @param _bondingCurve The address of the bonding curve contract
     * @dev Only the contract owner can call this function
     */
    function setBondingCurve(address _bondingCurve) external override onlyOwner {
        require(_bondingCurve != address(0), "Vault: bonding curve cannot be zero address");
        
        address oldBondingCurve = bondingCurve;
        bondingCurve = _bondingCurve;
        
        emit BondingCurveSet(oldBondingCurve, _bondingCurve);
    }
    
    /**
     * @notice Emergency withdraw function for owner to withdraw funds
     * @param amount The amount of tokens to withdraw
     * @dev Only the contract owner can call this function. Delegates to internal _emergencyWithdraw
     */
    function emergencyWithdraw(uint256 amount) external override onlyOwner {
        require(amount > 0, "Vault: amount must be greater than zero");
        
        _emergencyWithdraw(amount);
        
        emit EmergencyWithdraw(msg.sender, amount);
    }
    
    // ============ VIRTUAL FUNCTIONS ============
    
    /**
     * @notice Internal emergency withdraw implementation to be overridden by concrete contracts
     * @param amount The amount of tokens to withdraw
     * @dev Must be implemented by concrete vault contracts to define emergency withdrawal logic
     */
    function _emergencyWithdraw(uint256 amount) internal virtual;
    
    // ============ VIRTUAL FUNCTIONS ============
    
    /**
     * @notice Deposit tokens into the vault
     * @param token The token address to deposit
     * @param amount The amount of tokens to deposit
     * @param recipient The address that will own the deposited tokens
     * @dev Must be overridden by concrete contracts - implement onlyBondingCurve access control
     */
    function deposit(address token, uint256 amount, address recipient) external virtual override;
    
    /**
     * @notice Withdraw tokens from the vault
     * @param token The token address to withdraw
     * @param amount The amount of tokens to withdraw
     * @param recipient The address that will receive the tokens
     * @dev Must be overridden by concrete contracts - implement onlyBondingCurve access control
     */
    function withdraw(address token, uint256 amount, address recipient) external virtual override;
}