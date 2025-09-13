// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@vault/interfaces/IVault.sol";
import "./interfaces/IBondingToken.sol";
import "./interfaces/IBondingCurveHook.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Behodler3Tokenlaunch (B3)
 * @notice Bootstrap AMM using Virtual Pair architecture for token launches
 * @dev Refactored to eliminate code duplication and implement DRY principles
 * 
 * CRITICAL CONCEPT: Virtual Pair Architecture
 * - Virtual Pair: (inputToken, virtualL) where virtualL exists only as internal accounting
 * - Initial setup: (10000 inputToken, 100000000 virtualL) establishing k = 1,000,000,000,000
 * - Trading: Calculate virtual swap FIRST using xy=k, THEN mint actual bondingToken
 * - virtualL is NOT the same as bondingToken.totalSupply() - it's virtual/unminted
 * 
 * REFACTORING NOTES (Stories 002 & 003):
 * - Add operations use _calculateBondingTokensOut() for DRY principle compliance
 * - Remove operations use _calculateInputTokensOut() for symmetric architecture
 * - Both utilize _calculateVirtualPairQuote() for generalized quote logic
 * - Eliminates all code duplication between quote and actual operation functions
 */
contract Behodler3Tokenlaunch is ReentrancyGuard, Ownable {
    
    // ============ STATE VARIABLES ============
    
    /// @notice The input token being bootstrapped
    IERC20 public inputToken;
    
    /// @notice The bonding token representing liquidity positions
    IBondingToken public bondingToken;
    
    /// @notice The vault contract for token storage
    IVault public vault;
    
    /// @notice Whether the contract is locked for emergency purposes
    bool public locked;
    
    // Virtual Pair State - CRITICAL: These are separate from actual token balances
    /// @notice Virtual amount of input tokens in the pair (starts at 10000)
    uint256 public virtualInputTokens;
    
    /// @notice Virtual amount of L tokens in the pair (starts at 100000000)
    uint256 public virtualL;
    
    /// @notice The constant product k = virtualInputTokens * virtualL
    uint256 public constant K = 1_000_000_000_000; // 10000 * 100000000
    
    /// @notice Auto-lock functionality flag
    bool public autoLock;
    
    /// @notice The bonding curve hook for buy/sell operations
    IBondingCurveHook private bondingCurveHook;
    
    // ============ EVENTS ============
    
    event LiquidityAdded(address indexed user, uint256 inputAmount, uint256 bondingTokensOut);
    event LiquidityRemoved(address indexed user, uint256 bondingTokenAmount, uint256 inputTokensOut);
    event ContractLocked();
    event ContractUnlocked();
    event HookCalled(address indexed hook, address indexed user, string operation, uint256 fee, int256 delta);
    event FeeApplied(address indexed user, uint256 fee, string operation);
    event BondingTokenAdjusted(address indexed user, int256 adjustment, string operation);
    
    // ============ MODIFIERS ============
    
    modifier notLocked() {
        require(!locked, "B3: Contract is locked");
        _;
    }
    
    // ============ CONSTRUCTOR ============
    
    constructor(
        IERC20 _inputToken,
        IBondingToken _bondingToken,
        IVault _vault
    ) Ownable(msg.sender){
        // STUB: This should initialize but will cause test failures
        inputToken = _inputToken;
        bondingToken = _bondingToken;
        vault = _vault;
        
        // Initialize virtual pair to establish constant product k = 1,000,000,000,000
        virtualInputTokens = 10000; // Initial virtual input tokens
        virtualL = 100000000; // Initial virtual L tokens
    }
    
    // ============ INTERNAL HELPER FUNCTIONS ============
    
    /**
     * @notice Generalized quote calculation for virtual pair operations (DRY principle)
     * @dev Unified logic for both add and remove operations using virtual pair math formula
     * @param virtualFrom Current virtual amount of the token being reduced
     * @param virtualTo Current virtual amount of the token being increased  
     * @param inputAmount Amount of tokens being added to virtualTo
     * @return outputAmount Amount of tokens that would be reduced from virtualFrom
     */
    function _calculateVirtualPairQuote(
        uint256 virtualFrom, 
        uint256 virtualTo, 
        uint256 inputAmount
    ) 
        internal 
        pure 
        returns (uint256 outputAmount) 
    {
        // Generalized virtual pair formula: newVirtualFrom = K / (virtualTo + inputAmount)
        uint256 newVirtualFrom = K / (virtualTo + inputAmount);
        
        // Output amount = reduction in virtualFrom
        outputAmount = virtualFrom - newVirtualFrom;
        
        return outputAmount;
    }

    /**
     * @notice Calculate bonding tokens output for a given input amount using virtual pair math
     * @dev Uses generalized quote logic to eliminate duplication across quote system
     * @param inputAmount Amount of input tokens being added
     * @return bondingTokensOut Amount of bonding tokens that would be minted
     */
    function _calculateBondingTokensOut(uint256 inputAmount) 
        internal 
        view 
        returns (uint256 bondingTokensOut) 
    {
        // Use generalized quote: virtualL reduces, virtualInputTokens increases
        bondingTokensOut = _calculateVirtualPairQuote(virtualL, virtualInputTokens, inputAmount);
        
        return bondingTokensOut;
    }
    
    /**
     * @notice Calculate input tokens output for a given bonding token amount using virtual pair math
     * @dev Uses generalized quote logic to eliminate duplication across quote system
     * @param bondingTokenAmount Amount of bonding tokens being burned
     * @return inputTokensOut Amount of input tokens that would be received
     */
    function _calculateInputTokensOut(uint256 bondingTokenAmount) 
        internal 
        view 
        returns (uint256 inputTokensOut) 
    {
        // Use generalized quote: virtualInputTokens reduces, virtualL increases
        inputTokensOut = _calculateVirtualPairQuote(virtualInputTokens, virtualL, bondingTokenAmount);
        
        return inputTokensOut;
    }
    
    // ============ MAIN FUNCTIONS - ALL STUBS THAT WILL FAIL ============
    
    /**
     * @notice Add liquidity to the bootstrap AMM
     * @dev Uses refactored _calculateBondingTokensOut() for DRY principle compliance
     * @param inputAmount Amount of input tokens to add
     * @param minBondingTokens Minimum bonding tokens to receive (MEV protection)
     * @return bondingTokensOut Amount of bonding tokens minted
     */
    function addLiquidity(uint256 inputAmount, uint256 minBondingTokens) 
        external 
        nonReentrant 
        notLocked 
        returns (uint256 bondingTokensOut) 
    {
        require(inputAmount > 0, "B3: Input amount must be greater than 0");
        
        // Calculate base bonding tokens using refactored virtual pair math
        uint256 baseBondingTokens = _calculateBondingTokensOut(inputAmount);
        
        // Initialize variables for hook processing
        uint256 effectiveInputAmount = inputAmount;
        bondingTokensOut = baseBondingTokens;
        
        // Call buy hook if set
        if (address(bondingCurveHook) != address(0)) {
            (uint256 hookFee, int256 deltaBondingToken) = bondingCurveHook.buy(
                msg.sender, 
                baseBondingTokens, 
                inputAmount
            );
            
            // Emit hook called event
            emit HookCalled(address(bondingCurveHook), msg.sender, "buy", hookFee, deltaBondingToken);
            
            // Apply fee to input amount
            if (hookFee > 0) {
                require(hookFee <= 1000, "B3: Fee exceeds maximum");
                uint256 feeAmount = (inputAmount * hookFee) / 1000;
                effectiveInputAmount = inputAmount - feeAmount;
                emit FeeApplied(msg.sender, feeAmount, "buy");
                
                // Recalculate bonding tokens with reduced input
                bondingTokensOut = _calculateBondingTokensOut(effectiveInputAmount);
            }
            
            // Apply delta bonding token adjustment
            if (deltaBondingToken != 0) {
                int256 adjustedBondingAmount = int256(bondingTokensOut) + deltaBondingToken;
                require(adjustedBondingAmount > 0, "B3: Negative bonding token result");
                bondingTokensOut = uint256(adjustedBondingAmount);
                emit BondingTokenAdjusted(msg.sender, deltaBondingToken, "buy");
            }
        }
        
        // Check MEV protection
        require(bondingTokensOut >= minBondingTokens, "B3: Insufficient output amount");
        
        // Transfer input tokens from user to contract
        require(inputToken.transferFrom(msg.sender, address(this), inputAmount), "B3: Transfer failed");
        
        // Approve vault to spend input tokens
        require(inputToken.approve(address(vault), inputAmount), "B3: Approve failed");
        
        // Deposit input tokens to vault
        vault.deposit(address(inputToken), inputAmount, address(this));
        
        // Mint bonding tokens to user (only if amount > 0)
        if (bondingTokensOut > 0) {
            bondingToken.mint(msg.sender, bondingTokensOut);
        }
        
        // Update virtual pair state using base amounts (virtual pair math is independent of hook adjustments)
        virtualInputTokens += effectiveInputAmount;
        virtualL -= baseBondingTokens;
        
        emit LiquidityAdded(msg.sender, inputAmount, bondingTokensOut);
        
        return bondingTokensOut;
    }
    
    /**
     * @notice Remove liquidity from the bootstrap AMM
     * @dev Uses refactored _calculateInputTokensOut() for DRY principle compliance
     * @param bondingTokenAmount Amount of bonding tokens to burn
     * @param minInputTokens Minimum input tokens to receive (MEV protection)
     * @return inputTokensOut Amount of input tokens received
     */
    function removeLiquidity(uint256 bondingTokenAmount, uint256 minInputTokens) 
        external 
        nonReentrant 
        notLocked 
        returns (uint256 inputTokensOut) 
    {
        require(bondingTokenAmount > 0, "B3: Bonding token amount must be greater than 0");
        require(bondingToken.balanceOf(msg.sender) >= bondingTokenAmount, "B3: Insufficient bonding tokens");
        
        // Calculate base input tokens using refactored virtual pair math
        uint256 baseInputTokens = _calculateInputTokensOut(bondingTokenAmount);
        
        // Initialize variables for hook processing
        uint256 effectiveBondingAmount = bondingTokenAmount;
        inputTokensOut = baseInputTokens;
        
        // Call sell hook if set
        if (address(bondingCurveHook) != address(0)) {
            (uint256 hookFee, int256 deltaBondingToken) = bondingCurveHook.sell(
                msg.sender, 
                bondingTokenAmount, 
                baseInputTokens
            );
            
            // Emit hook called event
            emit HookCalled(address(bondingCurveHook), msg.sender, "sell", hookFee, deltaBondingToken);
            
            // Apply fee to bonding token amount
            if (hookFee > 0) {
                require(hookFee <= 1000, "B3: Fee exceeds maximum");
                uint256 feeAmount = (bondingTokenAmount * hookFee) / 1000;
                effectiveBondingAmount = bondingTokenAmount - feeAmount;
                emit FeeApplied(msg.sender, feeAmount, "sell");
                
                // Recalculate input tokens with reduced bonding tokens
                // Handle edge case where fee is 100% (effectiveBondingAmount = 0)
                if (effectiveBondingAmount > 0) {
                    inputTokensOut = _calculateInputTokensOut(effectiveBondingAmount);
                } else {
                    inputTokensOut = 0;
                }
            }
            
            // Apply delta bonding token adjustment
            if (deltaBondingToken != 0) {
                int256 adjustedBondingAmount = int256(effectiveBondingAmount) + deltaBondingToken;
                require(adjustedBondingAmount > 0, "B3: Invalid bonding token amount after adjustment");
                effectiveBondingAmount = uint256(adjustedBondingAmount);
                
                // Handle edge case where adjusted amount might be 0
                if (effectiveBondingAmount > 0) {
                    inputTokensOut = _calculateInputTokensOut(effectiveBondingAmount);
                } else {
                    inputTokensOut = 0;
                }
                emit BondingTokenAdjusted(msg.sender, deltaBondingToken, "sell");
            }
        }
        
        // Check MEV protection
        require(inputTokensOut >= minInputTokens, "B3: Insufficient output amount");
        
        // Burn bonding tokens from user
        bondingToken.burn(msg.sender, bondingTokenAmount);
        
        // Withdraw and transfer input tokens to user (only if amount > 0)
        if (inputTokensOut > 0) {
            vault.withdraw(address(inputToken), inputTokensOut, address(this));
            require(inputToken.transfer(msg.sender, inputTokensOut), "B3: Transfer failed");
        }
        
        // Update virtual pair state using base amounts (virtual pair math is independent of hook adjustments)  
        uint256 newVirtualInputTokens = K / (virtualL + bondingTokenAmount);
        virtualInputTokens = newVirtualInputTokens;
        virtualL += bondingTokenAmount;
        
        emit LiquidityRemoved(msg.sender, bondingTokenAmount, inputTokensOut);
        
        return inputTokensOut;
    }
    
    /**
     * @notice Quote how many bonding tokens would be received for adding liquidity
     * @dev Uses refactored _calculateBondingTokensOut() for consistent calculation with addLiquidity
     * @param inputAmount Amount of input tokens to add
     * @return bondingTokensOut Expected bonding tokens to be minted
     */
    function quoteAddLiquidity(uint256 inputAmount) 
        external 
        view 
        returns (uint256 bondingTokensOut) 
    {
        if (inputAmount == 0) return 0;
        
        // Calculate using refactored virtual pair math
        bondingTokensOut = _calculateBondingTokensOut(inputAmount);
        
        return bondingTokensOut;
    }
    
    /**
     * @notice Quote how many input tokens would be received for removing liquidity
     * @dev Uses refactored _calculateInputTokensOut() for consistent calculation with removeLiquidity
     * @param bondingTokenAmount Amount of bonding tokens to burn
     * @return inputTokensOut Expected input tokens to be received
     */
    function quoteRemoveLiquidity(uint256 bondingTokenAmount) 
        external 
        view 
        returns (uint256 inputTokensOut) 
    {
        if (bondingTokenAmount == 0) return 0;
        
        // Calculate using refactored virtual pair math
        inputTokensOut = _calculateInputTokensOut(bondingTokenAmount);
        
        return inputTokensOut;
    }
    
    // ============ OWNER FUNCTIONS - ALL STUBS ============
    
    /**
     * @notice Lock the contract to prevent operations
     */
    function lock() external onlyOwner {
        locked = true;
        emit ContractLocked();
    }
    
    /**
     * @notice Unlock the contract to allow operations
     */
    function unlock() external onlyOwner {
        locked = false;
        emit ContractUnlocked();
    }

    
    /**
     * @notice Set auto-lock functionality
     * @param _autoLock Whether to enable auto-lock
     */
    function setAutoLock(bool _autoLock) external onlyOwner {
        autoLock = _autoLock;
    }
    
    /**
     * @notice Set the bonding curve hook
     * @param _hook The hook contract address
     */
    function setHook(IBondingCurveHook _hook) external onlyOwner {
        bondingCurveHook = _hook;
    }
    
    /**
     * @notice Get the current bonding curve hook
     * @return The hook contract address
     */
    function getHook() external view returns (IBondingCurveHook) {
        return bondingCurveHook;
    }
    
    // ============ VIEW FUNCTIONS - ALL STUBS ============
    
    /**
     * @notice Get the current virtual pair state
     * @return inputTokens Virtual input tokens in the pair
     * @return lTokens Virtual L tokens in the pair
     * @return k The constant product
     */
    function getVirtualPair() external view returns (uint256 inputTokens, uint256 lTokens, uint256 k) {
        return (virtualInputTokens, virtualL, virtualInputTokens * virtualL);
    }
    
    /**
     * @notice Check if virtual pair is properly initialized
     * @return True if initialized correctly
     */
    function isVirtualPairInitialized() external view returns (bool) {
        return virtualInputTokens == 10000 && virtualL == 100000000;
    }
    
    /**
     * @notice Verify that virtualL != bondingToken.totalSupply()
     * @return True if they are different (as expected in virtual pair architecture)
     */
    function virtualLDifferentFromTotalSupply() external view returns (bool) {
        return virtualL != bondingToken.totalSupply();
    }
}