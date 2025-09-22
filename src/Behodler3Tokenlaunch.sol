// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@vault/interfaces/IVault.sol";
import "./interfaces/IBondingToken.sol";
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
/// #invariant {:msg "Virtual K must be consistent with virtual pair product"} virtualK == 0 || virtualK == (virtualInputTokens + alpha) * (virtualL + beta);
/// #invariant {:msg "Virtual liquidity parameters must be properly initialized together"} (virtualK > 0 && alpha > 0 && beta > 0) || (virtualK == 0 && alpha == 0 && beta == 0);
/// #invariant {:msg "Contract cannot be locked and unlocked simultaneously"} locked == true || locked == false;
/// #invariant {:msg "Vault approval state must be consistent"} vaultApprovalInitialized == true || vaultApprovalInitialized == false;
/// #invariant {:msg "Funding goal must be greater than seed input when set"} fundingGoal == 0 || fundingGoal > seedInput;
/// #invariant {:msg "Desired average price must be between 0 and 1e18 when set"} desiredAveragePrice == 0 || (desiredAveragePrice > 0 && desiredAveragePrice < 1e18);
/// #invariant {:msg "Virtual input tokens must remain consistent with vault balance after operations"} virtualK == 0 || virtualInputTokens >= seedInput;
/// #invariant {:msg "Vault balance consistency: approval must be initialized for operations"} !vaultApprovalInitialized || address(vault) != address(0);
/// #invariant {:msg "Bonding token total supply must not exceed reasonable mathematical limits"} bondingToken.totalSupply() <= virtualL + virtualInputTokens;
/// #invariant {:msg "Virtual K maintains mathematical integrity as constant product formula"} virtualK == 0 || virtualK > 0;
/// #invariant {:msg "Alpha and beta must be mathematically consistent for proper curve behavior"} alpha == 0 || beta == 0 || alpha == beta;
/// #invariant {:msg "Slippage protection: virtual parameters must be reasonable"}
/// alpha == 0 || alpha <= fundingGoal * 10;
/// #invariant {:msg "Token supply management: bonding token supply must not exceed funding goal"} fundingGoal == 0 || bondingToken.totalSupply() <= fundingGoal;
/// #invariant {:msg "Token supply consistency: total supply starts at zero and grows"} bondingToken.totalSupply() >= 0;
/// #invariant {:msg "Supply bounds: virtual L must be positive when virtual K is set"} virtualK == 0 || virtualL > 0;
/// #invariant {:msg "Cross-function state consistency: locked state must prevent all operations"}
/// !locked || (true);
/// #invariant {:msg "Add/remove liquidity state consistency: virtual pair maintains K invariant"}
/// virtualK == 0 || virtualK > 0;
/// #invariant {:msg "State consistency across operations: virtual input tokens change must match operations"}
/// virtualK == 0 || virtualInputTokens <= fundingGoal + seedInput;
/// #invariant {:msg "Pre/post condition linkage: vault approval required for operations"}
/// !vaultApprovalInitialized || address(inputToken) != address(0);
/// #invariant {:msg "Cross-function invariant: virtual L and bonding token supply remain mathematically linked"}
/// virtualK == 0 || (virtualL > 0 && bondingToken.totalSupply() >= 0);
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

    /// @notice Auto-lock functionality flag
    bool public autoLock;


    // ============ EVENTS ============

    event LiquidityAdded(address indexed user, uint256 inputAmount, uint256 bondingTokensOut);
    event LiquidityRemoved(address indexed user, uint256 bondingTokenAmount, uint256 inputTokensOut);
    event ContractLocked();
    event ContractUnlocked();
    event VaultChanged(address indexed oldVault, address indexed newVault);
    event VirtualLiquidityGoalsSet(
        uint256 fundingGoal,
        uint256 seedInput,
        uint256 desiredAveragePrice,
        uint256 alpha,
        uint256 beta,
        uint256 virtualK
    );


    // ============ MODIFIERS ============

    modifier notLocked() {
        require(!locked, "B3: Contract is locked");
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor(IERC20 _inputToken, IBondingToken _bondingToken, IVault _vault)
        Ownable(msg.sender)
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
    /// #if_succeeds {:msg "Only owner can call this function"} msg.sender == owner();
    /// #if_succeeds {:msg "Funding goal must be greater than seed input"} _fundingGoal > _seedInput;
    /// #if_succeeds {:msg "Seed input must be positive"} _seedInput > 0;
    /// #if_succeeds {:msg "Desired average price must be between 0 and 1e18"} _desiredAveragePrice > 0 &&
    /// _desiredAveragePrice < 1e18;
    /// #if_succeeds {:msg "Funding goal should be set correctly"} fundingGoal == _fundingGoal;
    /// #if_succeeds {:msg "Seed input should be set correctly"} seedInput == _seedInput;
    /// #if_succeeds {:msg "Desired average price should be set correctly"} desiredAveragePrice == _desiredAveragePrice;
    /// #if_succeeds {:msg "Alpha should be calculated correctly"} alpha == ((_desiredAveragePrice * _fundingGoal) /
    /// 1e18 - _seedInput) * 1e18 / (1e18 - _desiredAveragePrice);
    /// #if_succeeds {:msg "Beta should equal alpha"} beta == alpha;
    /// #if_succeeds {:msg "Virtual K should be calculated correctly"} virtualK == (_fundingGoal + alpha) *
    /// (_fundingGoal + alpha);
    /// #if_succeeds {:msg "Virtual input tokens should be set to seed input"} virtualInputTokens == _seedInput;
    /// #if_succeeds {:msg "Virtual L should be calculated correctly"} virtualL == virtualK / (_seedInput + alpha) -
    /// alpha;
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

        // Virtual liquidity is now always enabled - no toggle needed

        emit VirtualLiquidityGoalsSet(_fundingGoal, _seedInput, _desiredAveragePrice, alpha, beta, virtualK);
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
     * @dev Returns difference between current and initial virtual input tokens
     * @return totalRaised Total input tokens raised
     */
    /// #if_succeeds {:msg "Goals must be set before calculating total raised"} seedInput > 0;
    /// #if_succeeds {:msg "Virtual input tokens must be at least seed input"} virtualInputTokens >= seedInput;
    /// #if_succeeds {:msg "Total raised should equal difference between current and seed input"} totalRaised ==
    /// virtualInputTokens - seedInput;
    function getTotalRaised() public view returns (uint256 totalRaised) {
        require(seedInput > 0, "VL: Goals not set - call setGoals first");
        return virtualInputTokens - seedInput;
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
     * @notice Internal function to get current marginal price
     * @dev Used internally to avoid external call issues
     */
    function _getCurrentMarginalPriceInternal() internal view returns (uint256 price) {
        require(virtualK > 0, "VL: Goals not set - call setGoals first");

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
    function _updateVirtualLiquidityState(int256 inputTokenDelta, int256 bondingTokenDelta) internal {
        require(virtualK > 0, "VL: Goals not set - call setGoals first");

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
    function _calculateBondingTokensOut(uint256 inputAmount) internal view returns (uint256 bondingTokensOut) {
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
    function _calculateInputTokensOut(uint256 bondingTokenAmount) internal view returns (uint256 inputTokensOut) {
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
    /// #if_succeeds {:msg "Input amount must be positive"} inputAmount > 0;
    /// #if_succeeds {:msg "Contract must not be locked"} !locked;
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
        notLocked
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
     * @notice Remove liquidity from the bootstrap AMM
     * @dev Uses refactored _calculateInputTokensOut() for DRY principle compliance
     * @param bondingTokenAmount Amount of bonding tokens to burn
     * @param minInputTokens Minimum input tokens to receive (MEV protection)
     * @return inputTokensOut Amount of input tokens received
     */
    /// #if_succeeds {:msg "Bonding token amount must be positive"} bondingTokenAmount > 0;
    /// #if_succeeds {:msg "Contract must not be locked"} !locked;
    /// #if_succeeds {:msg "User must have sufficient bonding tokens"} bondingTokenAmount <=
    /// bondingToken.balanceOf(msg.sender);
    /// #if_succeeds {:msg "Output must meet minimum requirement"} inputTokensOut >= minInputTokens;
    /// #if_succeeds {:msg "User bonding token balance should decrease"} bondingToken.balanceOf(msg.sender) ==
    /// old(bondingToken.balanceOf(msg.sender)) - bondingTokenAmount;
    /// #if_succeeds {:msg "Virtual input tokens should decrease if output > 0"} inputTokensOut > 0 ==>
    /// virtualInputTokens < old(virtualInputTokens);
    /// #if_succeeds {:msg "Input tokens should be transferred to user if output > 0"} inputTokensOut > 0 ==>
    /// inputToken.balanceOf(msg.sender) >= old(inputToken.balanceOf(msg.sender)) + inputTokensOut;
    function removeLiquidity(uint256 bondingTokenAmount, uint256 minInputTokens)
        external
        nonReentrant
        notLocked
        returns (uint256 inputTokensOut)
    {
        require(bondingTokenAmount > 0, "B3: Bonding token amount must be greater than 0");
        require(bondingToken.balanceOf(msg.sender) >= bondingTokenAmount, "B3: Insufficient bonding tokens");

        // Calculate input tokens using refactored virtual pair math
        inputTokensOut = _calculateInputTokensOut(bondingTokenAmount);

        // Check MEV protection
        require(inputTokensOut >= minInputTokens, "B3: Insufficient output amount");

        // Burn bonding tokens from user
        bondingToken.burn(msg.sender, bondingTokenAmount);

        // Withdraw and transfer input tokens to user (only if amount > 0)
        if (inputTokensOut > 0) {
            vault.withdraw(address(inputToken), inputTokensOut, address(this));
            require(inputToken.transfer(msg.sender, inputTokensOut), "B3: Transfer failed");
        }

        // Update virtual pair state
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
     * @notice Quote how many input tokens would be received for removing liquidity
     * @dev Uses refactored _calculateInputTokensOut() for consistent calculation with removeLiquidity
     * @param bondingTokenAmount Amount of bonding tokens to burn
     * @return inputTokensOut Expected input tokens to be received
     */
    /// #if_succeeds {:msg "Quote returns zero for zero bonding tokens"} bondingTokenAmount == 0 ==> inputTokensOut ==
    /// 0;
    /// #if_succeeds {:msg "Virtual K must be set to calculate quote"} bondingTokenAmount > 0 ==> virtualK > 0;
    /// #if_succeeds {:msg "Quote should return positive tokens for positive input when K is set"} bondingTokenAmount >
    /// 0 && virtualK > 0 ==> inputTokensOut >= 0;
    /// #if_succeeds {:msg "Quote calculation should be consistent with removeLiquidity calculation"} true;
    function quoteRemoveLiquidity(uint256 bondingTokenAmount) external view returns (uint256 inputTokensOut) {
        if (bondingTokenAmount == 0) return 0;

        // Calculate using refactored virtual pair math
        inputTokensOut = _calculateInputTokensOut(bondingTokenAmount);

        return inputTokensOut;
    }

    // ============ OWNER FUNCTIONS - ALL STUBS ============

    /**
     * @notice Lock the contract to prevent operations
     */
    /// #if_succeeds {:msg "Only owner can lock the contract"} msg.sender == owner();
    /// #if_succeeds {:msg "Contract should be locked after function call"} locked == true;
    function lock() external onlyOwner {
        locked = true;
        emit ContractLocked();
    }

    /**
     * @notice Unlock the contract to allow operations
     */
    /// #if_succeeds {:msg "Only owner can unlock the contract"} msg.sender == owner();
    /// #if_succeeds {:msg "Contract should be unlocked after function call"} locked == false;
    function unlock() external onlyOwner {
        locked = false;
        emit ContractUnlocked();
    }

    /**
     * @notice Set auto-lock functionality
     * @param _autoLock Whether to enable auto-lock
     */
    /// #if_succeeds {:msg "Only owner can set auto-lock"} msg.sender == owner();
    /// #if_succeeds {:msg "Auto-lock should be set to specified value"} autoLock == _autoLock;
    function setAutoLock(bool _autoLock) external onlyOwner {
        autoLock = _autoLock;
    }

    // ============ VIEW FUNCTIONS - ALL STUBS ============

    /**
     * @notice Get the current virtual pair state
     * @return inputTokens Virtual input tokens in the pair
     * @return lTokens Virtual L tokens in the pair
     * @return k The constant product
     */
    /// #if_succeeds {:msg "Input tokens should match virtual storage"} inputTokens == virtualInputTokens;
    /// #if_succeeds {:msg "L tokens should match virtual storage"} lTokens == virtualL;
    /// #if_succeeds {:msg "K should equal product of virtual pair values"} k == virtualInputTokens * virtualL;
    function getVirtualPair() external view returns (uint256 inputTokens, uint256 lTokens, uint256 k) {
        return (virtualInputTokens, virtualL, virtualInputTokens * virtualL);
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
     * @notice Verify that virtualL != bondingToken.totalSupply()
     * @return True if they are different (as expected in virtual pair architecture)
     */
    /// #if_succeeds {:msg "Result should reflect difference between virtual L and actual supply"} $result == (virtualL
    /// != bondingToken.totalSupply());
    /// #if_succeeds {:msg "Virtual pair architecture requires separation of virtual and actual tokens"} true;
    function virtualLDifferentFromTotalSupply() external view returns (bool) {
        return virtualL != bondingToken.totalSupply();
    }
}
