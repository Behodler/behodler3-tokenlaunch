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
 *
 * APPROVAL FLOW (Story 010 - Gas Optimization with Deferred Approval):
 * - Constructor no longer performs vault approval to prevent deployment failures
 * - Vault approval is deferred until after deployment when vault authorizes this contract
 * - Owner must call initializeVaultApproval() after vault.setClient(address(this), true)
 * - This saves ~5000 gas per addLiquidity call by using max approval instead of per-transaction approvals
 * - Emergency disableToken() function allows revoking vault approval if needed
 * - Fallback safety check in addLiquidity ensures vault approval is initialized
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

    /// @notice Whether the vault approval has been initialized
    bool public vaultApprovalInitialized;

    // Virtual Pair State - CRITICAL: These are separate from actual token balances
    /// @notice Virtual amount of input tokens in the pair (starts at 10000)
    uint256 public virtualInputTokens;

    /// @notice Virtual amount of L tokens in the pair (starts at 100000000)
    uint256 public virtualL;

    /// @notice The constant product k = virtualInputTokens * virtualL
    uint256 public constant K = 1_000_000_000_000; // 10000 * 100000000

    // Virtual Liquidity Parameters for (x+α)(y+β)=k formula
    /// @notice Virtual liquidity offset for input tokens (α)
    uint256 public alpha;

    /// @notice Virtual liquidity offset for bonding tokens (β)
    uint256 public beta;

    /// @notice Virtual liquidity constant product k for (x+α)(y+β)=k
    uint256 public virtualK;

    /// @notice Whether virtual liquidity mode is enabled
    bool public virtualLiquidityEnabled;

    /// @notice Funding goal for virtual liquidity mode
    uint256 public fundingGoal;

    /// @notice Seed input amount for virtual liquidity mode
    uint256 public seedInput;

    /// @notice Desired average price for virtual liquidity mode (scaled by 1e18)
    uint256 public desiredAveragePrice;
    
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
    event VaultChanged(address indexed oldVault, address indexed newVault);
    event VirtualLiquidityGoalsSet(uint256 fundingGoal, uint256 seedInput, uint256 desiredAveragePrice, uint256 alpha, uint256 beta, uint256 virtualK);
    event VirtualLiquidityToggled(bool enabled);
    
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
        // Store references but defer approval until vault authorizes this contract
        inputToken = _inputToken;
        bondingToken = _bondingToken;
        vault = _vault;

        // Initialize virtual pair to establish constant product k = 1,000,000,000,000
        virtualInputTokens = 10000; // Initial virtual input tokens
        virtualL = 100000000; // Initial virtual L tokens

        // Vault approval is deferred to post-deployment initialization
        vaultApprovalInitialized = false;

        // Initialize virtual liquidity as disabled
        virtualLiquidityEnabled = false;
    }

    // ============ VIRTUAL LIQUIDITY FUNCTIONS ============

    /**
     * @notice Set goals for virtual liquidity bonding curve using (x+α)(y+β)=k formula
     * @dev Calculates α, β, and k based on desired goals using mathematical formulas
     * @param _fundingGoal Total amount of input tokens to raise (x_fin)
     * @param _seedInput Initial seed amount of input tokens (x_0)
     * @param _desiredAveragePrice Desired average price for the sale (P_ave), scaled by 1e18
     */
    function setGoals(uint256 _fundingGoal, uint256 _seedInput, uint256 _desiredAveragePrice) external onlyOwner {
        require(_fundingGoal > _seedInput, "VL: Funding goal must be greater than seed");
        require(_desiredAveragePrice > 0 && _desiredAveragePrice < 1e18, "VL: Average price must be between 0 and 1");
        require(_seedInput > 0, "VL: Seed input must be greater than 0");

        // Store goal parameters
        fundingGoal = _fundingGoal;
        seedInput = _seedInput;
        desiredAveragePrice = _desiredAveragePrice;

        // Calculate α using formula: α = (P_ave * x_fin - x_0) / (1 - P_ave)
        // All calculations in wei (1e18) precision
        uint256 numerator = (_desiredAveragePrice * _fundingGoal) / 1e18 - _seedInput;
        uint256 denominator = 1e18 - _desiredAveragePrice;
        alpha = (numerator * 1e18) / denominator;

        // Set β = α for equal final prices as specified in planning doc
        beta = alpha;

        // Calculate k = (x_fin + α)^2
        uint256 xFinPlusAlpha = _fundingGoal + alpha;
        virtualK = xFinPlusAlpha * xFinPlusAlpha; // Keep the full precision

        // Initialize virtual bonding token balance: y_0 = k/(x_0 + α) - α
        uint256 x0PlusAlpha = _seedInput + alpha;
        virtualL = virtualK / x0PlusAlpha - alpha;

        // Set virtual input tokens to seed amount
        virtualInputTokens = _seedInput;

        // Enable virtual liquidity mode
        virtualLiquidityEnabled = true;

        emit VirtualLiquidityGoalsSet(_fundingGoal, _seedInput, _desiredAveragePrice, alpha, beta, virtualK);
    }

    /**
     * @notice Toggle virtual liquidity mode on/off
     * @dev Allows switching between xy=k and (x+α)(y+β)=k formulas
     * @param _enabled Whether to enable virtual liquidity mode
     */
    function setVirtualLiquidityEnabled(bool _enabled) external onlyOwner {
        virtualLiquidityEnabled = _enabled;
        emit VirtualLiquidityToggled(_enabled);
    }

    /**
     * @notice Get current marginal price using virtual liquidity formula
     * @dev Returns price = (x+α)²/k scaled by 1e18
     * @return price Current marginal price scaled by 1e18
     */
    function getCurrentMarginalPrice() external view returns (uint256 price) {
        return _getCurrentMarginalPriceInternal();
    }

    /**
     * @notice Get average price achieved so far
     * @dev Returns total tokens raised divided by total bonding tokens issued
     * @return avgPrice Average price scaled by 1e18
     */
    function getAveragePrice() external view returns (uint256 avgPrice) {
        uint256 totalBondingTokens = bondingToken.totalSupply();
        if (totalBondingTokens == 0) return 0;

        uint256 totalRaised = getTotalRaised();
        avgPrice = (totalRaised * 1e18) / totalBondingTokens;
        return avgPrice;
    }

    /**
     * @notice Get total amount of input tokens raised so far
     * @dev Returns difference between current and initial virtual input tokens
     * @return totalRaised Total input tokens raised
     */
    function getTotalRaised() public view returns (uint256 totalRaised) {
        if (!virtualLiquidityEnabled) {
            return virtualInputTokens - 10000; // Default initial amount
        }
        return virtualInputTokens - seedInput;
    }

    /**
     * @notice Get initial marginal price P_0 = (P_ave)²
     * @dev Returns the theoretical initial price based on goals
     * @return initialPrice Initial marginal price scaled by 1e18
     */
    function getInitialMarginalPrice() external view returns (uint256 initialPrice) {
        return _getInitialMarginalPriceInternal();
    }

    /**
     * @notice Get final marginal price (should equal 1e18 when funding goal reached)
     * @dev Returns 1e18 as final price when x = y at funding goal
     * @return finalPrice Final marginal price scaled by 1e18
     */
    function getFinalMarginalPrice() external pure returns (uint256 finalPrice) {
        return 1e18; // Price equals 1 when x = y
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
        view
        returns (uint256 outputAmount)
    {
        if (virtualLiquidityEnabled) {
            // Use virtual liquidity formula: (x+α)(y+β)=k
            return _calculateVirtualLiquidityQuote(virtualFrom, virtualTo, inputAmount);
        } else {
            // Traditional xy=k formula: newVirtualFrom = K / (virtualTo + inputAmount)
            uint256 newVirtualFrom = K / (virtualTo + inputAmount);

            // Output amount = reduction in virtualFrom
            outputAmount = virtualFrom - newVirtualFrom;

            return outputAmount;
        }
    }

    /**
     * @notice Calculate quote using virtual liquidity formula (x+α)(y+β)=k
     * @dev Implements the offset bonding curve mathematics
     * @param virtualFrom Current virtual amount of the token being reduced
     * @param virtualTo Current virtual amount of the token being increased
     * @param inputAmount Amount of tokens being added to virtualTo
     * @return outputAmount Amount of tokens that would be reduced from virtualFrom
     */
    function _calculateVirtualLiquidityQuote(
        uint256 virtualFrom,
        uint256 virtualTo,
        uint256 inputAmount
    )
        internal
        view
        returns (uint256 outputAmount)
    {
        // Determine which offset to use based on token type
        uint256 fromOffset;
        uint256 toOffset;

        if (virtualFrom == virtualInputTokens) {
            // virtualFrom is input tokens, virtualTo is bonding tokens
            fromOffset = alpha;
            toOffset = beta;
        } else {
            // virtualFrom is bonding tokens, virtualTo is input tokens
            fromOffset = beta;
            toOffset = alpha;
        }

        // Calculate using (x+α)(y+β)=k formula
        // newVirtualFrom = k / (virtualTo + inputAmount + toOffset) - fromOffset
        uint256 denominator = virtualTo + inputAmount + toOffset;
        uint256 newVirtualFrom = virtualK / denominator - fromOffset;

        // Ensure we don't get negative results
        require(newVirtualFrom < virtualFrom, "VL: Invalid calculation result");

        // Output amount = reduction in virtualFrom
        outputAmount = virtualFrom - newVirtualFrom;

        return outputAmount;
    }

    /**
     * @notice Check that marginal price is within expected bounds
     * @dev Ensures price doesn't go below initial or above final bounds
     */
    function _checkPriceBounds() internal view {
        if (!virtualLiquidityEnabled) return;

        uint256 currentPrice = _getCurrentMarginalPriceInternal();
        uint256 initialPrice = _getInitialMarginalPriceInternal();
        uint256 finalPrice = 1e18; // Final price is always 1.0

        require(currentPrice >= initialPrice, "VL: Price below initial bound");
        require(currentPrice <= finalPrice, "VL: Price above final bound");
    }

    /**
     * @notice Internal function to get current marginal price
     * @dev Used internally to avoid external call issues
     */
    function _getCurrentMarginalPriceInternal() internal view returns (uint256 price) {
        if (!virtualLiquidityEnabled) {
            return (virtualInputTokens * 1e18) / virtualL;
        }

        uint256 xPlusAlpha = virtualInputTokens + alpha;
        // Calculate (x+α)²/k with proper scaling
        price = (xPlusAlpha * xPlusAlpha * 1e18) / virtualK;
        return price;
    }

    /**
     * @notice Internal function to get initial marginal price
     * @dev Used internally to avoid external call issues
     */
    function _getInitialMarginalPriceInternal() internal view returns (uint256 initialPrice) {
        if (!virtualLiquidityEnabled) return 0;
        initialPrice = (desiredAveragePrice * desiredAveragePrice) / 1e18;
        return initialPrice;
    }

    /**
     * @notice Update virtual pair state for virtual liquidity mode
     * @dev Updates state using virtual liquidity formula instead of traditional xy=k
     * @param inputTokenDelta Change in input tokens (positive for add, negative for remove)
     * @param bondingTokenDelta Change in bonding tokens (negative for add, positive for remove)
     */
    function _updateVirtualLiquidityState(int256 inputTokenDelta, int256 bondingTokenDelta) internal {
        if (!virtualLiquidityEnabled) return;

        // Update virtual input tokens
        if (inputTokenDelta >= 0) {
            virtualInputTokens += uint256(inputTokenDelta);
        } else {
            virtualInputTokens -= uint256(-inputTokenDelta);
        }

        // Update virtual bonding tokens
        if (bondingTokenDelta >= 0) {
            virtualL += uint256(bondingTokenDelta);
        } else {
            virtualL -= uint256(-bondingTokenDelta);
        }

        // Check price bounds after state update
        _checkPriceBounds();
    }

    /**
     * @dev Once off approve on vault to save gas
     * @param _token new input token address
     */
    function setInputToken(address _token) external onlyOwner{
      _setInputToken(IERC20(_token));
    }

    function _setInputToken(IERC20 _token) internal{
        inputToken = _token;

        // Only approve if vault has already authorized this contract
        // This prevents constructor failures when vault hasn't authorized us yet
        if (vaultApprovalInitialized) {
            require(inputToken.approve(address(vault), type(uint).max), "B3: Approve failed");
        }
    }

    /**
     * @notice Initialize vault approval after the vault has authorized this contract
     * @dev MUST be called by owner after vault.setClient(address(this), true)
     *      This defers the approval that would otherwise fail in constructor
     */
    function initializeVaultApproval() external onlyOwner {
        require(!vaultApprovalInitialized, "B3: Vault approval already initialized");

        // Perform the approval that was deferred from constructor
        require(inputToken.approve(address(vault), type(uint).max), "B3: Vault approval failed");

        vaultApprovalInitialized = true;
    }

    /**
     * @notice Emergency function to revoke vault approval for the input token
     * @dev Allows owner to disable vault operations in case of emergency
     */
    function disableToken() external onlyOwner {
        require(vaultApprovalInitialized, "B3: Vault approval not initialized");

        // Revoke approval from vault
        require(inputToken.approve(address(vault), 0), "B3: Approval revocation failed");

        vaultApprovalInitialized = false;
    }

    /**
     * @notice Set the vault address for the contract
     * @dev Owner-only function to update the vault contract address
     * @param _vault The new vault contract address
     */
    function setVault(address _vault) external onlyOwner {
        _setVault(IVault(_vault));
    }

    /**
     * @notice Internal function to set the vault address
     * @dev Sets vault address and resets approval state for security
     * @param _vault The new vault contract address
     */
    function _setVault(IVault _vault) internal {
        address oldVault = address(vault);
        vault = _vault;

        // Reset vault approval initialization to false when vault changes
        // This ensures the new vault must be properly authorized before operations
        vaultApprovalInitialized = false;

        emit VaultChanged(oldVault, address(_vault));
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

        // Fallback safety check: ensure vault approval is initialized
        // This prevents operations if approval was missed or revoked
        require(vaultApprovalInitialized, "B3: Vault approval not initialized - call initializeVaultApproval() first");
        
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
        
        // Deposit input tokens to vault
        vault.deposit(address(inputToken), inputAmount, address(this));
        
        // Mint bonding tokens to user (only if amount > 0)
        if (bondingTokensOut > 0) {
            bondingToken.mint(msg.sender, bondingTokensOut);
        }
        
        // Update virtual pair state using base amounts (virtual pair math is independent of hook adjustments)
        if (virtualLiquidityEnabled) {
            _updateVirtualLiquidityState(int256(effectiveInputAmount), -int256(baseBondingTokens));
        } else {
            virtualInputTokens += effectiveInputAmount;
            virtualL -= baseBondingTokens;
        }
        
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
        if (virtualLiquidityEnabled) {
            _updateVirtualLiquidityState(-int256(baseInputTokens), int256(bondingTokenAmount));
        } else {
            uint256 newVirtualInputTokens = K / (virtualL + bondingTokenAmount);
            virtualInputTokens = newVirtualInputTokens;
            virtualL += bondingTokenAmount;
        }
        
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