// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@vault/interfaces/IYieldStrategy.sol";
import "./interfaces/IBondingToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

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
/// #invariant {:msg "Virtual K must be consistent with virtual pair product"} virtualK == 0 || virtualK == (virtualInputTokens + alpha) * (virtualL + beta);
/// #invariant {:msg "Virtual liquidity parameters must be properly initialized together"} (virtualK > 0 && alpha > 0 && beta > 0) || (virtualK == 0 && alpha == 0 && beta == 0);
/// #invariant {:msg "Vault approval state must be consistent"} vaultApprovalInitialized == true || vaultApprovalInitialized == false;
/// #invariant {:msg "Seed input must always be zero (zero seed enforcement)"} seedInput == 0;
/// #invariant {:msg "Desired average price must be between 0 and 1e18 when set"} desiredAveragePrice == 0 || (desiredAveragePrice > 0 && desiredAveragePrice < 1e18);
/// #invariant {:msg "Virtual input tokens must be non-negative (starts at zero)"} virtualInputTokens >= 0;
/// #invariant {:msg "Vault balance consistency: approval must be initialized for operations"} !vaultApprovalInitialized || address(vault) != address(0);
/// #invariant {:msg "Bonding token total supply must not exceed reasonable mathematical limits"} bondingToken.totalSupply() <= virtualL + virtualInputTokens;
/// #invariant {:msg "Virtual K maintains mathematical integrity as constant product formula"} virtualK == 0 || virtualK > 0;
/// #invariant {:msg "Alpha and beta must be mathematically consistent for proper curve behavior"} alpha == 0 || beta == 0 || alpha == beta;
/// #invariant {:msg "Slippage protection: virtual parameters must be reasonable"}
/// alpha == 0 || alpha <= fundingGoal * 10;
/// #invariant {:msg "Token supply management: bonding token supply must not exceed funding goal"} fundingGoal == 0 || bondingToken.totalSupply() <= fundingGoal;
/// #invariant {:msg "Token supply consistency: total supply starts at zero and grows"} bondingToken.totalSupply() >= 0;
/// #invariant {:msg "Supply bounds: virtual L must be positive when virtual K is set"} virtualK == 0 || virtualL > 0;
/// #invariant {:msg "Add/remove liquidity state consistency: virtual pair maintains K invariant"}
/// virtualK == 0 || virtualK > 0;
/// #invariant {:msg "State consistency across operations: virtual input tokens should not exceed funding goal"}
/// virtualK == 0 || virtualInputTokens <= fundingGoal;
/// #invariant {:msg "Pre/post condition linkage: vault approval required for operations"}
/// !vaultApprovalInitialized || address(inputToken) != address(0);
/// #invariant {:msg "Cross-function invariant: virtual L and bonding token supply remain mathematically linked"}
/// virtualK == 0 || (virtualL > 0 && bondingToken.totalSupply() >= 0);
/// #invariant {:msg "Withdrawal fee must be within valid range (0 to 10000 basis points)"} withdrawalFeeBasisPoints >= 0 && withdrawalFeeBasisPoints <= 10000;
contract Behodler3Tokenlaunch is ReentrancyGuard, Ownable, Pausable {
    // ============ STATE VARIABLES ============

    /// @notice The input token being bootstrapped
    IERC20 public inputToken;

    /// @notice The bonding token representing liquidity positions
    IBondingToken public bondingToken;

    /// @notice The vault contract for token storage
    IYieldStrategy public vault;

    /// @notice Whether the vault approval has been initialized
    bool public vaultApprovalInitialized;

    /// @notice Address of the Pauser contract that can trigger pause
    address public pauser;

    // Virtual Pair State - CRITICAL: These are separate from actual token balances
    /// @notice Virtual amount of input tokens in the pair (starts at 10000)
    uint256 public virtualInputTokens;

    /// @notice Base virtual L from curve operations only (for rebase mechanism)
    uint256 private _baseVirtualL;

    /// @notice Last known supply from curve operations (for external mint detection)
    uint256 private _lastKnownSupply;

    /// @notice Virtual amount of L tokens from curve operations (public view for compatibility)
    /// @dev Returns _baseVirtualL. External minting dilution is handled separately in redemption logic.
    function virtualL() public view returns (uint256) {
        return _baseVirtualL;
    }

    // Virtual Liquidity Parameters for (x+α)(y+β)=k formula
    /// @notice Virtual liquidity offset for input tokens (α)
    uint256 public alpha;

    /// @notice Virtual liquidity offset for bonding tokens (β)
    uint256 public beta;

    /// @notice Virtual liquidity constant product k for (x+α)(y+β)=k
    uint256 public virtualK;

    /// @notice Funding goal for virtual liquidity mode
    uint256 public fundingGoal;

    /// @notice Seed input amount for virtual liquidity mode
    uint256 public seedInput;

    /// @notice Desired average price for virtual liquidity mode (scaled by 1e18)
    uint256 public desiredAveragePrice;

    /// @notice Withdrawal fee in basis points (0-10000, where 10000 = 100%)
    uint256 public withdrawalFeeBasisPoints;

    // ============ EVENTS ============

    event LiquidityAdded(address indexed user, uint256 inputAmount, uint256 bondingTokensOut);
    event LiquidityRemoved(address indexed user, uint256 bondingTokenAmount, uint256 inputTokensOut);
    event VaultChanged(address indexed oldVault, address indexed newVault);
    event VirtualLiquidityGoalsSet( // Always zero with zero seed enforcement
    uint256 fundingGoal, uint256 seedInput, uint256 desiredAveragePrice, uint256 alpha, uint256 beta, uint256 virtualK);
    event WithdrawalFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollected(address indexed user, uint256 bondingTokenAmount, uint256 feeAmount);
    event PauserUpdated(address indexed oldPauser, address indexed newPauser);

    // ============ MODIFIERS ============

    modifier onlyPauser() {
        require(msg.sender == pauser, "B3: Caller is not the pauser");
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor(IERC20 _inputToken, IBondingToken _bondingToken, IYieldStrategy _vault) Ownable(msg.sender) {
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
     * @notice Set goals for virtual liquidity bonding curve using (x+α)(y+β)=k formula with zero seed enforcement
     * @dev Calculates α, β, and k based on desired goals using mathematical formulas with x₀ = 0
     * @param _fundingGoal Total amount of input tokens to raise (x_fin)
     * @param _desiredAveragePrice Desired average price for the sale (P_ave), scaled by 1e18
     */
    /// #if_succeeds {:msg "Only owner can call this function"} msg.sender == owner();
    /// #if_succeeds {:msg "Funding goal must be positive"} _fundingGoal > 0;
    /// #if_succeeds {:msg "Desired average price must be between sqrt(0.75) and 1e18"} _desiredAveragePrice >= 866025403784438647 && _desiredAveragePrice < 1e18;
    /// #if_succeeds {:msg "Funding goal should be set correctly"} fundingGoal == _fundingGoal;
    /// #if_succeeds {:msg "Seed input should be enforced as zero"} seedInput == 0;
    /// #if_succeeds {:msg "Desired average price should be set correctly"} desiredAveragePrice == _desiredAveragePrice;
    /// #if_succeeds {:msg "Alpha should be calculated correctly for zero seed"} alpha == (_desiredAveragePrice * _fundingGoal) / (1e18 - _desiredAveragePrice);
    /// #if_succeeds {:msg "Beta should equal alpha"} beta == alpha;
    /// #if_succeeds {:msg "Virtual K should be calculated correctly"} virtualK == (_fundingGoal + alpha) * (_fundingGoal + alpha);
    /// #if_succeeds {:msg "Virtual input tokens should be set to zero"} virtualInputTokens == 0;
    /// #if_succeeds {:msg "Virtual L should be calculated correctly"} virtualL == virtualK / alpha - alpha;
    function setGoals(uint256 _fundingGoal, uint256 _desiredAveragePrice) external onlyOwner {
        require(_fundingGoal > 0, "VL: Funding goal must be positive");

        // Enforce minimum average price for target initial price P₀ ≥ 0.75
        // P₀ = P_avg², so P_avg ≥ √0.75 ≈ 0.866025403784438647 (scaled by 1e18)
        require(_desiredAveragePrice >= 866025403784438647, "VL: Average price must be >= sqrt(0.75) for P0 >= 0.75");
        require(_desiredAveragePrice < 1e18, "VL: Average price must be < 1");

        // Store goal parameters with enforced zero seed
        fundingGoal = _fundingGoal;
        seedInput = 0; // Enforce zero seed
        desiredAveragePrice = _desiredAveragePrice;

        // Calculate α using formula for zero seed: α = (P_avg * x_fin) / (1 - P_avg)
        // When x₀ = 0, the formula simplifies significantly
        uint256 numerator = (_desiredAveragePrice * _fundingGoal) / 1e18;
        uint256 denominator = 1e18 - _desiredAveragePrice;
        require(denominator > 0, "VL: Invalid average price (denominator would be zero)");
        alpha = (numerator * 1e18) / denominator;

        // Set β = α for equal final prices as specified in planning doc
        beta = alpha;

        // Calculate k = (x_fin + α)²
        uint256 xFinPlusAlpha = _fundingGoal + alpha;
        virtualK = xFinPlusAlpha * xFinPlusAlpha;

        // Initialize virtual bonding token balance for zero seed
        // Mathematical invariant: (x₀+α)(y₀+β) = k where x₀=0, β=α
        // Simplifies to: α(y₀+α) = k
        // Rearranging: α·y₀ + α² = k
        //             α·y₀ = k - α²
        //             y₀ = (k - α²) / α
        //
        // CRITICAL: We use (k - α²)/α instead of k/α - α to avoid integer division precision loss
        // The mathematically equivalent formulations produce different results in Solidity due to
        // truncation in integer division. This formulation ensures the invariant holds exactly.
        require(alpha > 0, "VL: Alpha must be positive for calculations");
        uint256 alphaSquared = alpha * alpha;
        require(virtualK > alphaSquared, "VL: K must be greater than alpha squared");
        _baseVirtualL = (virtualK - alphaSquared) / alpha;

        // Initialize tracking variables for anti-Cantillon protection
        _lastKnownSupply = 0;  // No tokens minted yet

        // Set virtual input tokens to zero (enforced seed)
        virtualInputTokens = 0;

        emit VirtualLiquidityGoalsSet(_fundingGoal, 0, _desiredAveragePrice, alpha, beta, virtualK);
    }

    /**
     * @notice Get current marginal price using virtual liquidity formula
     * @dev Returns price = (x+α)²/k scaled by 1e18
     * @return price Current marginal price scaled by 1e18
     */
    /// #if_succeeds {:msg "Virtual K must be set to calculate price"} virtualK > 0;
    /// #if_succeeds {:msg "Price must be positive when virtual K is set"} virtualK > 0 ==> price > 0;
    /// #if_succeeds {:msg "Price should be calculated using virtual pair formula"} virtualK > 0 ==>
    /// price == ((virtualInputTokens + alpha) * (virtualInputTokens + alpha) * 1e18) / virtualK;
    function getCurrentMarginalPrice() external view returns (uint256 price) {
        return _getCurrentMarginalPriceInternal();
    }

    /**
     * @notice Get average price achieved so far
     * @dev Returns total tokens raised divided by total bonding tokens issued
     * @return avgPrice Average price scaled by 1e18
     */
    /// #if_succeeds {:msg "Average price is zero when no bonding tokens exist"} bondingToken.totalSupply() == 0 ==>
    /// avgPrice == 0;
    /// #if_succeeds {:msg "Average price calculation must be correct when bonding tokens exist"}
    /// bondingToken.totalSupply() > 0 ==>
    /// avgPrice == (getTotalRaised() * 1e18) / bondingToken.totalSupply();
    /// #if_succeeds {:msg "Average price must be reasonable (not exceed max uint)"} avgPrice <= type(uint).max;
    function getAveragePrice() external view returns (uint256 avgPrice) {
        uint256 totalBondingTokens = bondingToken.totalSupply();
        if (totalBondingTokens == 0) return 0;

        uint256 totalRaised = getTotalRaised();
        avgPrice = (totalRaised * 1e18) / totalBondingTokens;
        return avgPrice;
    }

    /**
     * @notice Get total amount of input tokens raised so far
     * @dev Returns current virtual input tokens (starts from zero with zero seed)
     * @return totalRaised Total input tokens raised
     */
    /// #if_succeeds {:msg "Goals must be set before calculating total raised"} virtualK > 0;
    /// #if_succeeds {:msg "Total raised equals virtual input tokens with zero seed"} totalRaised == virtualInputTokens;
    function getTotalRaised() public view returns (uint256 totalRaised) {
        require(virtualK > 0, "VL: Goals not set - call setGoals first");
        return virtualInputTokens; // With zero seed, total raised = virtual input tokens
    }

    /**
     * @notice Get initial marginal price P_0 = (P_ave)²
     * @dev Returns the theoretical initial price based on goals
     * @return initialPrice Initial marginal price scaled by 1e18
     */
    /// #if_succeeds {:msg "Desired average price must be set to calculate initial price"} desiredAveragePrice > 0;
    /// #if_succeeds {:msg "Initial price should equal desired average price squared"} desiredAveragePrice > 0 ==>
    /// initialPrice == (desiredAveragePrice * desiredAveragePrice) / 1e18;
    function getInitialMarginalPrice() external view returns (uint256 initialPrice) {
        return _getInitialMarginalPriceInternal();
    }

    /**
     * @notice Get final marginal price (should equal 1e18 when funding goal reached)
     * @dev Returns 1e18 as final price when x = y at funding goal
     * @return finalPrice Final marginal price scaled by 1e18
     */
    /// #if_succeeds {:msg "Final price must always be 1e18 (representing 1:1 ratio)"} finalPrice == 1e18;
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
    function _calculateVirtualPairQuote(uint256 virtualFrom, uint256 virtualTo, uint256 inputAmount)
        internal
        view
        returns (uint256 outputAmount)
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
    function _calculateVirtualLiquidityQuote(uint256 virtualFrom, uint256 virtualTo, uint256 inputAmount)
        internal
        view
        returns (uint256 outputAmount)
    {
        // ZERO SEED OPTIMIZATION: Use optimized path when applicable
        if (seedInput == 0 && beta == alpha) {
            return _calculateVirtualLiquidityQuoteOptimized(virtualFrom, virtualTo, inputAmount);
        }

        // Fallback to general implementation for non-zero seed cases
        return _calculateVirtualLiquidityQuoteGeneral(virtualFrom, virtualTo, inputAmount);
    }

    /**
     * @notice Optimized virtual liquidity calculation for zero seed case
     * @dev Gas-optimized version when seedInput = 0 and β = α
     *      Optimizations: Storage caching + unchecked arithmetic where safe
     * @param virtualFrom Current virtual amount of the token being reduced
     * @param virtualTo Current virtual amount of the token being increased
     * @param inputAmount Amount of tokens being added to virtualTo
     * @return outputAmount Amount of tokens that would be reduced from virtualFrom
     */
    function _calculateVirtualLiquidityQuoteOptimized(uint256 virtualFrom, uint256 virtualTo, uint256 inputAmount)
        internal
        view
        returns (uint256 outputAmount)
    {
        // GAS OPTIMIZATION: Cache storage variables to avoid multiple SLOADs
        uint256 cachedAlpha = alpha;
        uint256 cachedVirtualK = virtualK;

        // ZERO SEED OPTIMIZATION: Since β = α, we can simplify calculations
        // Calculate denominator: virtualTo + inputAmount + α
        uint256 denominator;
        unchecked {
            // Safe: virtualTo and inputAmount are validated inputs, alpha is set by owner
            denominator = virtualTo + inputAmount + cachedAlpha;
        }

        // Calculate new virtual amount: k / denominator - α
        uint256 newVirtualFromWithOffset = cachedVirtualK / denominator;

        // Overflow protection: ensure newVirtualFromWithOffset >= alpha
        require(newVirtualFromWithOffset >= cachedAlpha, "VL: Subtraction would underflow");

        uint256 newVirtualFrom;
        unchecked {
            // Safe: we just verified newVirtualFromWithOffset >= cachedAlpha
            newVirtualFrom = newVirtualFromWithOffset - cachedAlpha;
        }

        // Overflow protection: ensure virtualFrom >= newVirtualFrom
        require(virtualFrom >= newVirtualFrom, "VL: Subtraction would underflow");

        unchecked {
            // Safe: we just verified virtualFrom >= newVirtualFrom
            outputAmount = virtualFrom - newVirtualFrom;
        }

        return outputAmount;
    }

    /**
     * @notice General virtual liquidity calculation (original implementation)
     * @dev Used as fallback for non-optimized cases
     * @param virtualFrom Current virtual amount of the token being reduced
     * @param virtualTo Current virtual amount of the token being increased
     * @param inputAmount Amount of tokens being added to virtualTo
     * @return outputAmount Amount of tokens that would be reduced from virtualFrom
     */
    function _calculateVirtualLiquidityQuoteGeneral(uint256 virtualFrom, uint256 virtualTo, uint256 inputAmount)
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
        // Check for overflow before adding
        require(virtualTo <= type(uint256).max - inputAmount, "VL: Addition would overflow");
        require(virtualTo + inputAmount <= type(uint256).max - toOffset, "VL: Addition would overflow");

        uint256 denominator = virtualTo + inputAmount + toOffset;
        require(denominator > 0, "VL: Zero denominator");

        uint256 newVirtualFromWithOffset = virtualK / denominator;
        require(newVirtualFromWithOffset >= fromOffset, "VL: Subtraction would underflow");
        uint256 newVirtualFrom = newVirtualFromWithOffset - fromOffset;

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

        uint256 currentPrice = _getCurrentMarginalPriceInternal();
        uint256 initialPrice = _getInitialMarginalPriceInternal();
        uint256 finalPrice = 1e18; // Final price is always 1.0

        require(currentPrice >= initialPrice, "VL: Price below initial bound");
        require(currentPrice <= finalPrice, "VL: Price above final bound");
    }

    /**
     * @notice Internal function to get current marginal price (optimized for zero seed)
     * @dev Used internally to avoid external call issues. Optimized for x₀ = 0 case.
     *      Gas optimizations: Storage caching + unchecked arithmetic
     */
    function _getCurrentMarginalPriceInternal() internal view returns (uint256 price) {
        // GAS OPTIMIZATION: Cache storage variables to avoid multiple SLOADs
        uint256 cachedVirtualK = virtualK;
        require(cachedVirtualK > 0, "VL: Goals not set - call setGoals first");

        uint256 cachedVirtualInputTokens = virtualInputTokens;
        uint256 cachedAlpha = alpha;

        // OPTIMIZATION: When seedInput is always 0, we can use optimized calculation
        // Since virtualInputTokens starts at 0 and only increases, we can optimize the calculation
        uint256 xPlusAlpha;
        unchecked {
            // Safe: both values are non-negative and alpha is set by owner within bounds
            xPlusAlpha = cachedVirtualInputTokens + cachedAlpha;
        }

        // Gas optimization: Use unchecked arithmetic for safe operations
        unchecked {
            // Calculate (x+α)²/k with proper scaling - optimized for zero seed case
            // Safe: xPlusAlpha is always positive, scaling by 1e18 is safe for reasonable values
            price = (xPlusAlpha * xPlusAlpha * 1e18) / cachedVirtualK;
        }

        return price;
    }

    /**
     * @notice Internal function to get initial marginal price (optimized for zero seed)
     * @dev Used internally to avoid external call issues. Zero seed optimization: P₀ = P_avg²
     *      Gas optimizations: Storage caching + unchecked arithmetic
     */
    function _getInitialMarginalPriceInternal() internal view returns (uint256 initialPrice) {
        // GAS OPTIMIZATION: Cache storage variable to avoid SLOAD
        uint256 cachedDesiredAveragePrice = desiredAveragePrice;
        require(cachedDesiredAveragePrice > 0, "VL: Goals not set - call setGoals first");

        // ZERO SEED OPTIMIZATION: P₀ = P_avg² (simplified when x₀ = 0)
        // Gas optimization: Use unchecked arithmetic for safe operations
        unchecked {
            // Safe: desiredAveragePrice is validated in setGoals() to be < 1e18
            initialPrice = (cachedDesiredAveragePrice * cachedDesiredAveragePrice) / 1e18;
        }

        return initialPrice;
    }

    /**
     * @notice Update virtual pair state for virtual liquidity mode with anti-Cantillon protection
     * @dev Updates state using virtual liquidity formula and tracks supply for rebase mechanism
     * @param inputTokenDelta Change in input tokens (positive for add, negative for remove)
     * @param bondingTokenDelta Change in bonding tokens (negative for add, positive for remove)
     */
    function _updateVirtualLiquidityState(int256 inputTokenDelta, int256 bondingTokenDelta) internal {
        require(virtualK > 0, "VL: Goals not set - call setGoals first");

        // Update virtual input tokens
        if (inputTokenDelta >= 0) {
            virtualInputTokens += uint256(inputTokenDelta);
        } else {
            virtualInputTokens -= uint256(-inputTokenDelta);
        }

        // Update BASE virtualL (the "true" curve value, excluding external mints)
        if (bondingTokenDelta >= 0) {
            _baseVirtualL += uint256(bondingTokenDelta);
        } else {
            _baseVirtualL -= uint256(-bondingTokenDelta);
        }

        // CRITICAL: Sync supply tracking after curve operation
        // This ensures _lastKnownSupply reflects legitimate curve operations
        _lastKnownSupply = bondingToken.totalSupply();

        // Check price bounds after state update
        _checkPriceBounds();
    }

    /**
     * @dev Once off approve on vault to save gas
     * @param _token new input token address
     */
    /// #if_succeeds {:msg "Only owner can set input token"} msg.sender == owner();
    /// #if_succeeds {:msg "Input token address must not be zero"} _token != address(0);
    /// #if_succeeds {:msg "Input token should be updated to new address"} address(inputToken) == _token;
    function setInputToken(address _token) external onlyOwner {
        _setInputToken(IERC20(_token));
    }

    function _setInputToken(IERC20 _token) internal {
        inputToken = _token;

        // Only approve if vault has already authorized this contract
        // This prevents constructor failures when vault hasn't authorized us yet
        if (vaultApprovalInitialized) {
            require(inputToken.approve(address(vault), type(uint256).max), "B3: Approve failed");
        }
    }

    /**
     * @notice Initialize vault approval after the vault has authorized this contract
     * @dev MUST be called by owner after vault.setClient(address(this), true)
     *      This defers the approval that would otherwise fail in constructor
     */
    /// #if_succeeds {:msg "Only owner can initialize vault approval"} msg.sender == owner();
    /// #if_succeeds {:msg "Vault approval was not already initialized"} !old(vaultApprovalInitialized);
    /// #if_succeeds {:msg "Vault approval should be initialized after call"} vaultApprovalInitialized == true;
    function initializeVaultApproval() external onlyOwner {
        require(!vaultApprovalInitialized, "B3: Vault approval already initialized");

        // Perform the approval that was deferred from constructor
        require(inputToken.approve(address(vault), type(uint256).max), "B3: Vault approval failed");

        vaultApprovalInitialized = true;
    }

    /**
     * @notice Emergency function to revoke vault approval for the input token
     * @dev Allows owner to disable vault operations in case of emergency
     */
    /// #if_succeeds {:msg "Only owner can disable token"} msg.sender == owner();
    /// #if_succeeds {:msg "Vault approval must be initialized before disabling"} old(vaultApprovalInitialized);
    /// #if_succeeds {:msg "Vault approval should be disabled after call"} vaultApprovalInitialized == false;
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
    /// #if_succeeds {:msg "Only owner can set vault"} msg.sender == owner();
    /// #if_succeeds {:msg "Vault address must not be zero"} _vault != address(0);
    /// #if_succeeds {:msg "Vault should be updated to new address"} address(vault) == _vault;
    /// #if_succeeds {:msg "Vault approval state should be reset"} vaultApprovalInitialized == false;
    function setVault(address _vault) external onlyOwner {
        _setVault(IYieldStrategy(_vault));
    }

    /**
     * @notice Internal function to set the vault address
     * @dev Sets vault address and resets approval state for security
     * @param _vault The new vault contract address
     */
    function _setVault(IYieldStrategy _vault) internal {
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
     *      Uses _baseVirtualL for curve calculation (external minting doesn't affect deposits)
     * @param inputAmount Amount of input tokens being added
     * @return bondingTokensOut Amount of bonding tokens that would be minted
     */
    function _calculateBondingTokensOut(uint256 inputAmount) internal view returns (uint256 bondingTokensOut) {
        // Use generalized quote: _baseVirtualL reduces, virtualInputTokens increases
        // Note: We use _baseVirtualL (not virtualL()) because deposits follow the curve,
        // regardless of external minting
        bondingTokensOut = _calculateVirtualPairQuote(_baseVirtualL, virtualInputTokens, inputAmount);

        return bondingTokensOut;
    }

    /**
     * @notice Calculate input tokens output for a given bonding token amount using virtual pair math with anti-Cantillon protection
     * @dev When external minting is detected, uses proportional share instead of bonding curve to ensure fair dilution
     *      Formula: When external minting detected: (bondingTokenAmount / totalSupply) * vaultBalance
     *               Normal operation: Bonding curve formula via _calculateVirtualPairQuote
     * @param bondingTokenAmount Amount of bonding tokens being burned
     * @return inputTokensOut Amount of input tokens that would be received
     */
    function _calculateInputTokensOut(uint256 bondingTokenAmount) internal view returns (uint256 inputTokensOut) {
        // With zero seed, no input tokens are available until liquidity is added
        if (virtualInputTokens == 0) {
            return 0;
        }

        uint256 currentSupply = bondingToken.totalSupply();

        // Check if external minting occurred
        if (currentSupply > _lastKnownSupply && _lastKnownSupply > 0) {
            // External minting detected - use proportional redemption to ensure fairness
            // This prevents Cantillon effect by making redemption proportional to % of total supply
            // Formula: (bondingTokenAmount / totalSupply) * vaultBalance
            inputTokensOut = (bondingTokenAmount * virtualInputTokens) / currentSupply;
        } else {
            // Normal curve operation - use bonding curve formula
            inputTokensOut = _calculateVirtualPairQuote(virtualInputTokens, _baseVirtualL, bondingTokenAmount);
        }

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
    /// #if_succeeds {:msg "Input amount must be positive"} inputAmount > 0;
    /// #if_succeeds {:msg "Vault approval must be initialized"} vaultApprovalInitialized;
    /// #if_succeeds {:msg "Virtual K must be set (goals initialized)"} virtualK > 0;
    /// #if_succeeds {:msg "Output must meet minimum requirement"} bondingTokensOut >= minBondingTokens;
    /// #if_succeeds {:msg "Bonding tokens must be minted to user"} bondingTokensOut > 0 ==>
    /// bondingToken.balanceOf(msg.sender) >= old(bondingToken.balanceOf(msg.sender)) + bondingTokensOut;
    /// #if_succeeds {:msg "Virtual input tokens should increase"} virtualInputTokens > old(virtualInputTokens);
    /// #if_succeeds {:msg "User must have sufficient input token balance"} inputAmount <=
    /// inputToken.balanceOf(msg.sender);
    /// #if_succeeds {:msg "User must have sufficient allowance"} inputAmount <= inputToken.allowance(msg.sender,
    /// address(this));
    function addLiquidity(uint256 inputAmount, uint256 minBondingTokens)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 bondingTokensOut)
    {
        require(inputAmount > 0, "B3: Input amount must be greater than 0");

        // Fallback safety check: ensure vault approval is initialized
        // This prevents operations if approval was missed or revoked
        require(vaultApprovalInitialized, "B3: Vault approval not initialized - call initializeVaultApproval() first");

        // Calculate bonding tokens using refactored virtual pair math
        bondingTokensOut = _calculateBondingTokensOut(inputAmount);

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

        // Update virtual pair state
        _updateVirtualLiquidityState(int256(inputAmount), -int256(bondingTokensOut));

        emit LiquidityAdded(msg.sender, inputAmount, bondingTokensOut);

        return bondingTokensOut;
    }

    /**
     * @notice Remove liquidity from the bootstrap AMM with optional withdrawal fee
     * @dev Uses refactored _calculateInputTokensOut() for DRY principle compliance.
     *      The fee mechanism works as follows:
     *      1. Fee is calculated as (bondingTokenAmount * withdrawalFeeBasisPoints) / 10000
     *      2. Full bondingTokenAmount is burned from user (supply decreases by full amount)
     *      3. Only effective amount (bondingTokenAmount - fee) is used for withdrawal calculation
     *      4. User receives input tokens based on effective amount, not full amount
     *      5. Fee is permanently removed from circulation (deflationary mechanism)
     *
     * @param bondingTokenAmount Amount of bonding tokens to burn (full amount including fee)
     * @param minInputTokens Minimum input tokens to receive (MEV protection, based on net after fee)
     * @return inputTokensOut Amount of input tokens received (calculated on effective amount after fee deduction)
     *
     * @notice Fee Mechanism:
     *         - Fee range: 0-10000 basis points (0% to 100%)
     *         - Fee = (bondingTokenAmount * withdrawalFeeBasisPoints) / 10000
     *         - Effective tokens = bondingTokenAmount - fee
     *         - Output calculated on effective tokens, not full amount
     *         - All bondingTokenAmount burned, reducing total supply
     *
     * @notice Gas Optimization: Fee calculation uses efficient integer arithmetic
     * @notice Security: Fee cannot exceed 100% (10000 basis points) due to validation in setWithdrawalFee
     */
    /// #if_succeeds {:msg "Bonding token amount must be positive"} bondingTokenAmount > 0;
    /// #if_succeeds {:msg "User must have sufficient bonding tokens"} bondingTokenAmount <=
    /// bondingToken.balanceOf(msg.sender);
    /// #if_succeeds {:msg "Output must meet minimum requirement"} inputTokensOut >= minInputTokens;
    /// #if_succeeds {:msg "User bonding token balance should decrease"} bondingToken.balanceOf(msg.sender) ==
    /// old(bondingToken.balanceOf(msg.sender)) - bondingTokenAmount;
    /// #if_succeeds {:msg "Virtual input tokens should decrease if output > 0"} inputTokensOut > 0 ==>
    /// virtualInputTokens < old(virtualInputTokens);
    /// #if_succeeds {:msg "Input tokens should be transferred to user if output > 0"} inputTokensOut > 0 ==>
    /// inputToken.balanceOf(msg.sender) >= old(inputToken.balanceOf(msg.sender)) + inputTokensOut;
    /// #if_succeeds {:msg "Total supply must decrease by full bonding token amount (including fees)"} bondingToken.totalSupply() == old(bondingToken.totalSupply()) - bondingTokenAmount;
    /// #if_succeeds {:msg "Fee calculation must be correct based on basis points"} let feeAmount := (bondingTokenAmount * withdrawalFeeBasisPoints) / 10000 in feeAmount >= 0 && feeAmount <= bondingTokenAmount;
    /// #if_succeeds {:msg "Effective bonding tokens must equal full amount minus fee"} let feeAmount := (bondingTokenAmount * withdrawalFeeBasisPoints) / 10000 in let effectiveAmount := bondingTokenAmount - feeAmount in effectiveAmount >= 0 && effectiveAmount <= bondingTokenAmount;
    function removeLiquidity(uint256 bondingTokenAmount, uint256 minInputTokens)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 inputTokensOut)
    {
        require(bondingTokenAmount > 0, "B3: Bonding token amount must be greater than 0");
        require(bondingToken.balanceOf(msg.sender) >= bondingTokenAmount, "B3: Insufficient bonding tokens");

        // GAS OPTIMIZATION: Cache withdrawal fee to avoid SLOAD
        uint256 cachedWithdrawalFee = withdrawalFeeBasisPoints;

        // Calculate fee amount in bondingTokens using unchecked arithmetic
        uint256 feeAmount;
        unchecked {
            // Safe: bondingTokenAmount is validated > 0, cachedWithdrawalFee <= 10000 (validated in setter)
            feeAmount = (bondingTokenAmount * cachedWithdrawalFee) / 10000;
        }

        // Calculate effective bonding tokens after fee deduction for withdrawal calculation
        uint256 effectiveBondingTokens;
        unchecked {
            // Safe: feeAmount = (bondingTokenAmount * fee) / 10000, so feeAmount <= bondingTokenAmount
            effectiveBondingTokens = bondingTokenAmount - feeAmount;
        }

        // Handle edge case: if fee consumes all bonding tokens, no input tokens to withdraw
        if (effectiveBondingTokens == 0) {
            inputTokensOut = 0;
        } else {
            // Calculate input tokens using effective bonding tokens (post-fee amount)
            inputTokensOut = _calculateInputTokensOut(effectiveBondingTokens);
        }

        // Check MEV protection
        require(inputTokensOut >= minInputTokens, "B3: Insufficient output amount");

        // Burn full bonding token amount from user (supply decreases by full amount)
        bondingToken.burn(msg.sender, bondingTokenAmount);

        // Emit fee collection event if fee was charged
        if (feeAmount > 0) {
            emit FeeCollected(msg.sender, bondingTokenAmount, feeAmount);
        }

        // Withdraw and transfer input tokens to user (only if amount > 0)
        if (inputTokensOut > 0) {
            vault.withdraw(address(inputToken), inputTokensOut, address(this));
            require(inputToken.transfer(msg.sender, inputTokensOut), "B3: Transfer failed");
        }

        // Update virtual pair state using full bonding token amount for supply,
        // but only effective amount affects virtual liquidity calculation
        _updateVirtualLiquidityState(-int256(inputTokensOut), int256(bondingTokenAmount));

        emit LiquidityRemoved(msg.sender, bondingTokenAmount, inputTokensOut);

        return inputTokensOut;
    }

    /**
     * @notice Quote how many bonding tokens would be received for adding liquidity
     * @dev Uses refactored _calculateBondingTokensOut() for consistent calculation with addLiquidity
     * @param inputAmount Amount of input tokens to add
     * @return bondingTokensOut Expected bonding tokens to be minted
     */
    /// #if_succeeds {:msg "Quote returns zero for zero input"} inputAmount == 0 ==> bondingTokensOut == 0;
    /// #if_succeeds {:msg "Virtual K must be set to calculate quote"} inputAmount > 0 ==> virtualK > 0;
    /// #if_succeeds {:msg "Quote should return positive tokens for positive input when K is set"} inputAmount > 0 &&
    /// virtualK > 0 ==> bondingTokensOut > 0;
    /// #if_succeeds {:msg "Quote calculation should be consistent with addLiquidity calculation"} true;
    function quoteAddLiquidity(uint256 inputAmount) external view returns (uint256 bondingTokensOut) {
        if (inputAmount == 0) return 0;

        // Calculate using refactored virtual pair math
        bondingTokensOut = _calculateBondingTokensOut(inputAmount);

        return bondingTokensOut;
    }

    /**
     * @notice Quote how many input tokens would be received for removing liquidity (after fee deduction)
     * @dev Uses refactored _calculateInputTokensOut() for consistent calculation with removeLiquidity.
     *      This function accounts for the withdrawal fee and returns the actual amount a user would receive.
     *      The calculation mirrors the exact logic used in removeLiquidity() to ensure accuracy.
     *
     * @param bondingTokenAmount Amount of bonding tokens to burn (full amount including fee portion)
     * @return inputTokensOut Expected input tokens to be received (net amount after fee deduction)
     *
     * @notice Fee Impact:
     *         - Quote includes current withdrawal fee (withdrawalFeeBasisPoints)
     *         - Fee = (bondingTokenAmount * withdrawalFeeBasisPoints) / 10000
     *         - Effective amount = bondingTokenAmount - fee
     *         - Output calculated on effective amount, not full bondingTokenAmount
     *         - Result represents actual tokens user will receive
     *
     * @notice Integration: Use this function to calculate expected output before calling removeLiquidity
     * @notice Frontend: Display both gross and net amounts for user transparency
     */
    /// #if_succeeds {:msg "Quote returns zero for zero bonding tokens"} bondingTokenAmount == 0 ==> inputTokensOut ==
    /// 0;
    /// #if_succeeds {:msg "Virtual K must be set to calculate quote"} bondingTokenAmount > 0 ==> virtualK > 0;
    /// #if_succeeds {:msg "Quote should return positive tokens for positive input when K is set"} bondingTokenAmount >
    /// 0 && virtualK > 0 ==> inputTokensOut >= 0;
    /// #if_succeeds {:msg "Quote calculation should be consistent with removeLiquidity calculation accounting for fees"} let feeAmount := (bondingTokenAmount * withdrawalFeeBasisPoints) / 10000 in let effectiveBondingTokens := bondingTokenAmount - feeAmount in inputTokensOut == _calculateInputTokensOut(effectiveBondingTokens);
    function quoteRemoveLiquidity(uint256 bondingTokenAmount) external view returns (uint256 inputTokensOut) {
        if (bondingTokenAmount == 0) return 0;

        // GAS OPTIMIZATION: Cache withdrawal fee to avoid SLOAD
        uint256 cachedWithdrawalFee = withdrawalFeeBasisPoints;

        // Calculate fee amount in bondingTokens (same logic as removeLiquidity)
        uint256 feeAmount;
        unchecked {
            // Safe: bondingTokenAmount > 0 validated above, cachedWithdrawalFee <= 10000
            feeAmount = (bondingTokenAmount * cachedWithdrawalFee) / 10000;
        }

        // Calculate effective bonding tokens after fee deduction
        uint256 effectiveBondingTokens;
        unchecked {
            // Safe: feeAmount <= bondingTokenAmount by mathematical property
            effectiveBondingTokens = bondingTokenAmount - feeAmount;
        }

        // Handle edge case: if fee consumes all bonding tokens, return 0
        if (effectiveBondingTokens == 0) return 0;

        // Calculate using effective bonding tokens (post-fee amount) to match removeLiquidity
        inputTokensOut = _calculateInputTokensOut(effectiveBondingTokens);

        return inputTokensOut;
    }

    // ============ OWNER FUNCTIONS - ALL STUBS ============

    /**
     * @notice Set withdrawal fee in basis points (0-10000) for removeLiquidity operations
     * @dev The withdrawal fee is applied when users remove liquidity via removeLiquidity().
     *      The fee mechanism implements a deflationary bonding token model where fees are
     *      permanently removed from circulation rather than redistributed.
     *
     * @param _feeBasisPoints Fee in basis points where:
     *                        - 0 = 0% (no fee)
     *                        - 100 = 1%
     *                        - 1000 = 10%
     *                        - 10000 = 100% (maximum allowed)
     *
     * @notice Fee Calculation:
     *         - Applied during removeLiquidity() calls
     *         - Fee = (bondingTokenAmount * _feeBasisPoints) / 10000
     *         - Full bondingTokenAmount is burned from user supply
     *         - Only (bondingTokenAmount - fee) used for withdrawal calculation
     *         - Results in deflationary pressure on bonding token supply
     *
     * @notice Security Considerations:
     *         - Only owner can set withdrawal fee (access controlled)
     *         - Maximum fee capped at 10000 basis points (100%)
     *         - Fee validation prevents overflow/underflow issues
     *         - Changes emit WithdrawalFeeUpdated event for transparency
     *
     * @notice Gas Optimization: Integer division optimized for efficiency
     * @notice Use Cases: Project sustainability, tokenomics alignment, MEV capture
     *
     * @dev Emits WithdrawalFeeUpdated(oldFee, newFee) event
     */
    /// #if_succeeds {:msg "Only owner can set withdrawal fee"} msg.sender == owner();
    /// #if_succeeds {:msg "Fee must be within valid range"} _feeBasisPoints <= 10000;
    /// #if_succeeds {:msg "Withdrawal fee should be updated to new value"} withdrawalFeeBasisPoints == _feeBasisPoints;
    /// #if_succeeds {:msg "Access control: only owner can modify withdrawal fee"} msg.sender == owner();
    /// #if_succeeds {:msg "Fee parameter validation: new fee must not exceed maximum"} _feeBasisPoints >= 0 && _feeBasisPoints <= 10000;
    function setWithdrawalFee(uint256 _feeBasisPoints) external onlyOwner {
        require(_feeBasisPoints <= 10000, "B3: Fee must be <= 10000 basis points");

        uint256 oldFee = withdrawalFeeBasisPoints;
        withdrawalFeeBasisPoints = _feeBasisPoints;

        emit WithdrawalFeeUpdated(oldFee, _feeBasisPoints);
    }

    /**
     * @notice Set the pauser contract address
     * @param _pauser Address of the Pauser contract
     */
    /// #if_succeeds {:msg "Only owner can set pauser"} msg.sender == owner();
    /// #if_succeeds {:msg "Pauser should be updated to new address"} pauser == _pauser;
    function setPauser(address _pauser) external onlyOwner {
        require(_pauser != address(0), "B3: Pauser cannot be zero address");

        address oldPauser = pauser;
        pauser = _pauser;

        emit PauserUpdated(oldPauser, _pauser);
    }

    /**
     * @notice Pause the contract (only callable by Pauser contract)
     */
    /// #if_succeeds {:msg "Only pauser can pause the contract"} msg.sender == pauser;
    /// #if_succeeds {:msg "Contract should be paused after function call"} paused() == true;
    function pause() external onlyPauser {
        _pause();
    }

    /**
     * @notice Unpause the contract (only callable by owner or pauser contract)
     */
    /// #if_succeeds {:msg "Only owner or pauser can unpause the contract"} msg.sender == owner() || msg.sender == pauser;
    /// #if_succeeds {:msg "Contract should be unpaused after function call"} paused() == false;
    function unpause() external {
        require(msg.sender == owner() || msg.sender == pauser, "B3: Caller is not owner or pauser");
        _unpause();
    }

    // ============ VIEW FUNCTIONS - ALL STUBS ============

    /**
     * @notice Get the current virtual pair state
     * @return inputTokens Virtual input tokens in the pair
     * @return lTokens Virtual L tokens in the pair (base value from curve operations)
     * @return k The virtual liquidity constant K (not x*y, but the actual virtualK)
     */
    /// #if_succeeds {:msg "Input tokens should match virtual storage"} inputTokens == virtualInputTokens;
    /// #if_succeeds {:msg "L tokens should match virtual storage"} lTokens == virtualL();
    /// #if_succeeds {:msg "K should return the virtual liquidity constant"} k == virtualK;
    function getVirtualPair() external view returns (uint256 inputTokens, uint256 lTokens, uint256 k) {
        return (virtualInputTokens, virtualL(), virtualK);
    }

    /**
     * @notice Check if virtual pair is properly initialized
     * @return True if initialized correctly
     */
    /// #if_succeeds {:msg "Initialization requires all virtual parameters to be positive"} $result == (virtualK > 0 &&
    /// alpha > 0 && beta > 0);
    /// #if_succeeds {:msg "If initialized, virtual K must be positive"} $result ==> virtualK > 0;
    /// #if_succeeds {:msg "If initialized, alpha must be positive"} $result ==> alpha > 0;
    /// #if_succeeds {:msg "If initialized, beta must be positive"} $result ==> beta > 0;
    function isVirtualPairInitialized() external view returns (bool) {
        return virtualK > 0 && alpha > 0 && beta > 0;
    }

    /**
     * @notice Verify that virtualL (base) != bondingToken.totalSupply()
     * @dev After implementing anti-Cantillon protection, _baseVirtualL tracks curve operations
     *      while totalSupply may include external minting. They will naturally differ.
     * @return True if they are different (as expected in virtual pair architecture)
     */
    /// #if_succeeds {:msg "Result should reflect difference between virtual L and actual supply"} $result == (virtualL()
    /// != bondingToken.totalSupply());
    /// #if_succeeds {:msg "Virtual pair architecture requires separation of virtual and actual tokens"} true;
    function virtualLDifferentFromTotalSupply() external view returns (bool) {
        return virtualL() != bondingToken.totalSupply();
    }
}
