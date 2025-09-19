// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@vault/interfaces/IVault.sol";
import "./interfaces/IBondingToken.sol";
import "./interfaces/IBondingCurveHook.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

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
contract Behodler3Tokenlaunch is ReentrancyGuard, Ownable, EIP712 {
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
    uint public virtualInputTokens;

    /// @notice Virtual amount of L tokens in the pair (starts at 100000000)
    uint public virtualL;

    // Virtual Liquidity Parameters for (x+α)(y+β)=k formula
    /// @notice Virtual liquidity offset for input tokens (α)
    uint public alpha;

    /// @notice Virtual liquidity offset for bonding tokens (β)
    uint public beta;

    /// @notice Virtual liquidity constant product k for (x+α)(y+β)=k
    uint public virtualK;

    /// @notice Funding goal for virtual liquidity mode
    uint public fundingGoal;

    /// @notice Seed input amount for virtual liquidity mode
    uint public seedInput;

    /// @notice Desired average price for virtual liquidity mode (scaled by 1e18)
    uint public desiredAveragePrice;

    /// @notice Auto-lock functionality flag
    bool public autoLock;

    /// @notice The bonding curve hook for buy/sell operations
    IBondingCurveHook private bondingCurveHook;

    // ============ EIP-2612 PERMIT VARIABLES ============

    /// @notice Mapping of user addresses to their current nonce for permit functionality
    mapping(address => uint) private _nonces;

    /// @notice EIP-712 typehash for the permit function
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice Name used for EIP-712 domain separator
    string private constant _EIP712_NAME = "Behodler3Tokenlaunch";

    /// @notice Version used for EIP-712 domain separator
    string private constant _EIP712_VERSION = "1";

    // ============ EVENTS ============

    event LiquidityAdded(address indexed user, uint inputAmount, uint bondingTokensOut);
    event LiquidityRemoved(address indexed user, uint bondingTokenAmount, uint inputTokensOut);
    event ContractLocked();
    event ContractUnlocked();
    event HookCalled(address indexed hook, address indexed user, string operation, uint fee, int delta);
    event FeeApplied(address indexed user, uint fee, string operation);
    event BondingTokenAdjusted(address indexed user, int adjustment, string operation);
    event VaultChanged(address indexed oldVault, address indexed newVault);
    event VirtualLiquidityGoalsSet(
        uint fundingGoal, uint seedInput, uint desiredAveragePrice, uint alpha, uint beta, uint virtualK
    );

    // ============ EIP-2612 PERMIT EVENTS ============

    /// @notice Emitted when a permit is used for token approval
    event PermitUsed(address indexed owner, address indexed spender, uint value, uint nonce, uint deadline);

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
    )
        Ownable(msg.sender)
        EIP712(_EIP712_NAME, _EIP712_VERSION)
    {
        // Store references but defer approval until vault authorizes this contract
        inputToken = _inputToken;
        bondingToken = _bondingToken;
        vault = _vault;

        // Vault approval is deferred to post-deployment initialization
        vaultApprovalInitialized = false;

        // Virtual liquidity parameters will be set via setGoals()
        // No default initialization - must call setGoals() before operations
    }

    // ============ VIRTUAL LIQUIDITY FUNCTIONS ============

    /**
     * @notice Set goals for virtual liquidity bonding curve using (x+α)(y+β)=k formula
     * @dev Calculates α, β, and k based on desired goals using mathematical formulas
     * @param _fundingGoal Total amount of input tokens to raise (x_fin)
     * @param _seedInput Initial seed amount of input tokens (x_0)
     * @param _desiredAveragePrice Desired average price for the sale (P_ave), scaled by 1e18
     */
    function setGoals(uint _fundingGoal, uint _seedInput, uint _desiredAveragePrice) external onlyOwner {
        require(_fundingGoal > _seedInput, "VL: Funding goal must be greater than seed");
        require(_desiredAveragePrice > 0 && _desiredAveragePrice < 1e18, "VL: Average price must be between 0 and 1");
        require(_seedInput > 0, "VL: Seed input must be greater than 0");

        // Store goal parameters
        fundingGoal = _fundingGoal;
        seedInput = _seedInput;
        desiredAveragePrice = _desiredAveragePrice;

        // Calculate α using formula: α = (P_ave * x_fin - x_0) / (1 - P_ave)
        // All calculations in wei (1e18) precision
        uint numerator = (_desiredAveragePrice * _fundingGoal) / 1e18 - _seedInput;
        uint denominator = 1e18 - _desiredAveragePrice;
        alpha = (numerator * 1e18) / denominator;

        // Set β = α for equal final prices as specified in planning doc
        beta = alpha;

        // Calculate k = (x_fin + α)^2
        uint xFinPlusAlpha = _fundingGoal + alpha;
        virtualK = xFinPlusAlpha * xFinPlusAlpha; // Keep the full precision

        // Initialize virtual bonding token balance: y_0 = k/(x_0 + α) - α
        uint x0PlusAlpha = _seedInput + alpha;
        virtualL = virtualK / x0PlusAlpha - alpha;

        // Set virtual input tokens to seed amount
        virtualInputTokens = _seedInput;

        // Virtual liquidity is now always enabled - no toggle needed

        emit VirtualLiquidityGoalsSet(_fundingGoal, _seedInput, _desiredAveragePrice, alpha, beta, virtualK);
    }

    /**
     * @notice Get current marginal price using virtual liquidity formula
     * @dev Returns price = (x+α)²/k scaled by 1e18
     * @return price Current marginal price scaled by 1e18
     */
    function getCurrentMarginalPrice() external view returns (uint price) {
        return _getCurrentMarginalPriceInternal();
    }

    /**
     * @notice Get average price achieved so far
     * @dev Returns total tokens raised divided by total bonding tokens issued
     * @return avgPrice Average price scaled by 1e18
     */
    function getAveragePrice() external view returns (uint avgPrice) {
        uint totalBondingTokens = bondingToken.totalSupply();
        if (totalBondingTokens == 0) return 0;

        uint totalRaised = getTotalRaised();
        avgPrice = (totalRaised * 1e18) / totalBondingTokens;
        return avgPrice;
    }

    /**
     * @notice Get total amount of input tokens raised so far
     * @dev Returns difference between current and initial virtual input tokens
     * @return totalRaised Total input tokens raised
     */
    function getTotalRaised() public view returns (uint totalRaised) {
        require(seedInput > 0, "VL: Goals not set - call setGoals first");
        return virtualInputTokens - seedInput;
    }

    /**
     * @notice Get initial marginal price P_0 = (P_ave)²
     * @dev Returns the theoretical initial price based on goals
     * @return initialPrice Initial marginal price scaled by 1e18
     */
    function getInitialMarginalPrice() external view returns (uint initialPrice) {
        return _getInitialMarginalPriceInternal();
    }

    /**
     * @notice Get final marginal price (should equal 1e18 when funding goal reached)
     * @dev Returns 1e18 as final price when x = y at funding goal
     * @return finalPrice Final marginal price scaled by 1e18
     */
    function getFinalMarginalPrice() external pure returns (uint finalPrice) {
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
        uint virtualFrom,
        uint virtualTo,
        uint inputAmount
    )
        internal
        view
        returns (uint outputAmount)
    {
        // Always use virtual liquidity formula: (x+α)(y+β)=k
        require(virtualK > 0, "VL: Goals not set - call setGoals first");
        return _calculateVirtualLiquidityQuote(virtualFrom, virtualTo, inputAmount);
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
        uint virtualFrom,
        uint virtualTo,
        uint inputAmount
    )
        internal
        view
        returns (uint outputAmount)
    {
        // Determine which offset to use based on token type
        uint fromOffset;
        uint toOffset;

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
        uint denominator = virtualTo + inputAmount + toOffset;
        uint newVirtualFrom = virtualK / denominator - fromOffset;

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
        require(virtualK > 0, "VL: Goals not set - call setGoals first");

        uint currentPrice = _getCurrentMarginalPriceInternal();
        uint initialPrice = _getInitialMarginalPriceInternal();
        uint finalPrice = 1e18; // Final price is always 1.0

        require(currentPrice >= initialPrice, "VL: Price below initial bound");
        require(currentPrice <= finalPrice, "VL: Price above final bound");
    }

    /**
     * @notice Internal function to get current marginal price
     * @dev Used internally to avoid external call issues
     */
    function _getCurrentMarginalPriceInternal() internal view returns (uint price) {
        require(virtualK > 0, "VL: Goals not set - call setGoals first");

        uint xPlusAlpha = virtualInputTokens + alpha;
        // Calculate (x+α)²/k with proper scaling
        price = (xPlusAlpha * xPlusAlpha * 1e18) / virtualK;
        return price;
    }

    /**
     * @notice Internal function to get initial marginal price
     * @dev Used internally to avoid external call issues
     */
    function _getInitialMarginalPriceInternal() internal view returns (uint initialPrice) {
        require(desiredAveragePrice > 0, "VL: Goals not set - call setGoals first");
        initialPrice = (desiredAveragePrice * desiredAveragePrice) / 1e18;
        return initialPrice;
    }

    /**
     * @notice Update virtual pair state for virtual liquidity mode
     * @dev Updates state using virtual liquidity formula instead of traditional xy=k
     * @param inputTokenDelta Change in input tokens (positive for add, negative for remove)
     * @param bondingTokenDelta Change in bonding tokens (negative for add, positive for remove)
     */
    function _updateVirtualLiquidityState(int inputTokenDelta, int bondingTokenDelta) internal {
        require(virtualK > 0, "VL: Goals not set - call setGoals first");

        // Update virtual input tokens
        if (inputTokenDelta >= 0) {
            virtualInputTokens += uint(inputTokenDelta);
        } else {
            virtualInputTokens -= uint(-inputTokenDelta);
        }

        // Update virtual bonding tokens
        if (bondingTokenDelta >= 0) {
            virtualL += uint(bondingTokenDelta);
        } else {
            virtualL -= uint(-bondingTokenDelta);
        }

        // Check price bounds after state update
        _checkPriceBounds();
    }

    /**
     * @dev Once off approve on vault to save gas
     * @param _token new input token address
     */
    function setInputToken(address _token) external onlyOwner {
        _setInputToken(IERC20(_token));
    }

    function _setInputToken(IERC20 _token) internal {
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
    function _calculateBondingTokensOut(uint inputAmount) internal view returns (uint bondingTokensOut) {
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
    function _calculateInputTokensOut(uint bondingTokenAmount) internal view returns (uint inputTokensOut) {
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
    function addLiquidity(
        uint inputAmount,
        uint minBondingTokens
    )
        external
        nonReentrant
        notLocked
        returns (uint bondingTokensOut)
    {
        require(inputAmount > 0, "B3: Input amount must be greater than 0");

        // Fallback safety check: ensure vault approval is initialized
        // This prevents operations if approval was missed or revoked
        require(vaultApprovalInitialized, "B3: Vault approval not initialized - call initializeVaultApproval() first");

        // Calculate base bonding tokens using refactored virtual pair math
        uint baseBondingTokens = _calculateBondingTokensOut(inputAmount);

        // Initialize variables for hook processing
        uint effectiveInputAmount = inputAmount;
        bondingTokensOut = baseBondingTokens;

        // Call buy hook if set
        if (address(bondingCurveHook) != address(0)) {
            (uint hookFee, int deltaBondingToken) = bondingCurveHook.buy(msg.sender, baseBondingTokens, inputAmount);

            // Emit hook called event
            emit HookCalled(address(bondingCurveHook), msg.sender, "buy", hookFee, deltaBondingToken);

            // Apply fee to input amount
            if (hookFee > 0) {
                require(hookFee <= 1000, "B3: Fee exceeds maximum");
                uint feeAmount = (inputAmount * hookFee) / 1000;
                effectiveInputAmount = inputAmount - feeAmount;
                emit FeeApplied(msg.sender, feeAmount, "buy");

                // Recalculate bonding tokens with reduced input
                bondingTokensOut = _calculateBondingTokensOut(effectiveInputAmount);
            }

            // Apply delta bonding token adjustment
            if (deltaBondingToken != 0) {
                int adjustedBondingAmount = int(bondingTokensOut) + deltaBondingToken;
                require(adjustedBondingAmount > 0, "B3: Negative bonding token result");
                bondingTokensOut = uint(adjustedBondingAmount);
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
        _updateVirtualLiquidityState(int(effectiveInputAmount), -int(baseBondingTokens));

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
    function removeLiquidity(
        uint bondingTokenAmount,
        uint minInputTokens
    )
        external
        nonReentrant
        notLocked
        returns (uint inputTokensOut)
    {
        require(bondingTokenAmount > 0, "B3: Bonding token amount must be greater than 0");
        require(bondingToken.balanceOf(msg.sender) >= bondingTokenAmount, "B3: Insufficient bonding tokens");

        // Calculate base input tokens using refactored virtual pair math
        uint baseInputTokens = _calculateInputTokensOut(bondingTokenAmount);

        // Initialize variables for hook processing
        uint effectiveBondingAmount = bondingTokenAmount;
        inputTokensOut = baseInputTokens;

        // Call sell hook if set
        if (address(bondingCurveHook) != address(0)) {
            (uint hookFee, int deltaBondingToken) =
                bondingCurveHook.sell(msg.sender, bondingTokenAmount, baseInputTokens);

            // Emit hook called event
            emit HookCalled(address(bondingCurveHook), msg.sender, "sell", hookFee, deltaBondingToken);

            // Apply fee to bonding token amount
            if (hookFee > 0) {
                require(hookFee <= 1000, "B3: Fee exceeds maximum");
                uint feeAmount = (bondingTokenAmount * hookFee) / 1000;
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
                int adjustedBondingAmount = int(effectiveBondingAmount) + deltaBondingToken;
                require(adjustedBondingAmount > 0, "B3: Invalid bonding token amount after adjustment");
                effectiveBondingAmount = uint(adjustedBondingAmount);

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
        _updateVirtualLiquidityState(-int(baseInputTokens), int(bondingTokenAmount));

        emit LiquidityRemoved(msg.sender, bondingTokenAmount, inputTokensOut);

        return inputTokensOut;
    }

    /**
     * @notice Quote how many bonding tokens would be received for adding liquidity
     * @dev Uses refactored _calculateBondingTokensOut() for consistent calculation with addLiquidity
     * @param inputAmount Amount of input tokens to add
     * @return bondingTokensOut Expected bonding tokens to be minted
     */
    function quoteAddLiquidity(uint inputAmount) external view returns (uint bondingTokensOut) {
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
    function quoteRemoveLiquidity(uint bondingTokenAmount) external view returns (uint inputTokensOut) {
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
    function getVirtualPair() external view returns (uint inputTokens, uint lTokens, uint k) {
        return (virtualInputTokens, virtualL, virtualInputTokens * virtualL);
    }

    /**
     * @notice Check if virtual pair is properly initialized
     * @return True if initialized correctly
     */
    function isVirtualPairInitialized() external view returns (bool) {
        return virtualK > 0 && alpha > 0 && beta > 0;
    }

    /**
     * @notice Verify that virtualL != bondingToken.totalSupply()
     * @return True if they are different (as expected in virtual pair architecture)
     */
    function virtualLDifferentFromTotalSupply() external view returns (bool) {
        return virtualL != bondingToken.totalSupply();
    }

    // ============ EIP-2612 PERMIT FUNCTIONS ============

    /**
     * @notice Implements EIP-2612 permit functionality for gasless approvals
     * @dev Allows token holder to approve spender via signature instead of transaction
     * @param owner The token owner granting the approval
     * @param spender The address being approved to spend tokens
     * @param value The amount of tokens to approve
     * @param deadline The timestamp after which the permit is no longer valid
     * @param v The recovery byte of the signature
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        require(deadline >= block.timestamp, "B3: Permit expired");
        require(owner != address(0), "B3: Invalid owner");
        require(spender != address(0), "B3: Invalid spender");

        uint nonce = _nonces[owner];

        // Increment nonce to prevent replay attacks
        _nonces[owner]++;

        // Check if the input token supports EIP-2612 permit
        try IERC20Permit(address(inputToken)).permit(owner, spender, value, deadline, v, r, s) {
            // If input token has native permit support, use it directly
            emit PermitUsed(owner, spender, value, nonce, deadline);
        } catch {
            // If input token doesn't support permit, we need a different approach
            // For now, revert as we cannot directly approve tokens we don't control
            revert("B3: Input token does not support permit");
        }
    }

    /**
     * @notice Permit-enabled version of addLiquidity
     * @dev Combines permit and addLiquidity in one transaction for gasless approval
     * @param inputAmount Amount of input tokens to add
     * @param minBondingTokens Minimum bonding tokens to receive (MEV protection)
     * @param deadline The timestamp after which the permit is no longer valid
     * @param v The recovery byte of the signature
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     * @return bondingTokensOut Amount of bonding tokens minted
     */
    function addLiquidityWithPermit(
        uint inputAmount,
        uint minBondingTokens,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        nonReentrant
        notLocked
        returns (uint bondingTokensOut)
    {
        require(inputAmount > 0, "B3: Input amount must be greater than 0");

        // Fallback safety check: ensure vault approval is initialized
        require(vaultApprovalInitialized, "B3: Vault approval not initialized - call initializeVaultApproval() first");

        // First try to use permit (will fail gracefully if not supported)
        try this.permit(msg.sender, address(this), inputAmount, deadline, v, r, s) {
            // Permit succeeded, proceed with addLiquidity
        } catch {
            // Permit failed - check if user has sufficient allowance instead
            require(
                inputToken.allowance(msg.sender, address(this)) >= inputAmount,
                "B3: Insufficient allowance and permit failed"
            );
        }

        // Calculate base bonding tokens using refactored virtual pair math
        uint baseBondingTokens = _calculateBondingTokensOut(inputAmount);

        // Initialize variables for hook processing
        uint effectiveInputAmount = inputAmount;
        bondingTokensOut = baseBondingTokens;

        // Call buy hook if set
        if (address(bondingCurveHook) != address(0)) {
            (uint hookFee, int deltaBondingToken) = bondingCurveHook.buy(msg.sender, baseBondingTokens, inputAmount);

            // Emit hook called event
            emit HookCalled(address(bondingCurveHook), msg.sender, "buy", hookFee, deltaBondingToken);

            // Apply fee to input amount
            if (hookFee > 0) {
                require(hookFee <= 1000, "B3: Fee exceeds maximum");
                uint feeAmount = (inputAmount * hookFee) / 1000;
                effectiveInputAmount = inputAmount - feeAmount;
                emit FeeApplied(msg.sender, feeAmount, "buy");

                // Recalculate bonding tokens with reduced input
                bondingTokensOut = _calculateBondingTokensOut(effectiveInputAmount);
            }

            // Apply delta bonding token adjustment
            if (deltaBondingToken != 0) {
                int adjustedBondingAmount = int(bondingTokensOut) + deltaBondingToken;
                require(adjustedBondingAmount > 0, "B3: Negative bonding token result");
                bondingTokensOut = uint(adjustedBondingAmount);
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
        _updateVirtualLiquidityState(int(effectiveInputAmount), -int(baseBondingTokens));

        emit LiquidityAdded(msg.sender, inputAmount, bondingTokensOut);

        return bondingTokensOut;
    }

    /**
     * @notice Returns the current nonce for the given owner
     * @dev Part of EIP-2612 standard interface
     * @param owner The address to query the nonce for
     * @return The current nonce for the owner
     */
    function nonces(address owner) external view returns (uint) {
        return _nonces[owner];
    }

    /**
     * @notice Returns the domain separator for EIP-712 signatures
     * @dev Part of EIP-2612 standard interface
     * @return The domain separator hash
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Checks if the contract supports EIP-2612 permit functionality
     * @dev Returns true if permit is supported (EIP-165 compatible)
     * @param interfaceId The interface identifier to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC20Permit).interfaceId || interfaceId == 0x01ffc9a7; // EIP-165 interface ID
    }
}
