# Behodler3 TokenLaunch API Documentation

## Overview

The Behodler3 TokenLaunch contract provides a simplified architecture for bootstrapping AMM using Virtual Pair architecture. This version **does not support EIP-2612 permit functionality** and uses standard ERC20 approve/transfer patterns for enhanced security and compatibility.

## Contract Address

Deploy using the script at `script/Deploy.s.sol` or manually with the constructor parameters.

## Architecture

### Virtual Pair System

The contract uses a virtual pair architecture:
- **Virtual Pair**: (inputToken, virtualL) where virtualL exists only as internal accounting
- **Initial Setup**: (10000 inputToken, 100000000 virtualL) establishing k = 1,000,000,000,000
- **Trading**: Calculate virtual swap FIRST using xy=k, THEN mint actual bondingToken
- **virtualL**: NOT the same as bondingToken.totalSupply() - it's virtual/unminted

### Approval Requirements

**IMPORTANT**: This contract uses standard ERC20 patterns:
- Users must `approve()` the TokenLaunch contract before calling `addLiquidity()`
- No permit signatures are supported or required
- Enhanced security through simplified approval mechanisms

## Constructor

```solidity
constructor(
    IERC20 _inputToken,
    IBondingToken _bondingToken,
    IVault _vault
)
```

**Parameters:**
- `_inputToken`: The ERC20 token being bootstrapped
- `_bondingToken`: The bonding token contract for liquidity positions
- `_vault`: The vault contract for token storage

## Core Functions

### Liquidity Operations

#### addLiquidity

```solidity
function addLiquidity(uint256 inputAmount, uint256 minBondingTokens)
    external
    nonReentrant
    returns (uint256 bondingTokensOut)
```

Adds liquidity to the pool using standard ERC20 approve/transfer pattern.

**Prerequisites:**
- User must approve the contract: `inputToken.approve(contractAddress, inputAmount)`
- Contract must not be locked
- Vault approval must be initialized

**Parameters:**
- `inputAmount`: Amount of input tokens to deposit
- `minBondingTokens`: Minimum bonding tokens expected (slippage protection)

**Returns:**
- `bondingTokensOut`: Actual bonding tokens minted

**Events Emitted:**
- `LiquidityAdded(user, inputAmount, bondingTokensOut)`

**Example Usage:**
```javascript
// Approve tokens first
await inputToken.approve(tokenLaunchAddress, ethers.parseEther("100"));

// Add liquidity
await tokenLaunch.addLiquidity(
    ethers.parseEther("100"),  // inputAmount
    ethers.parseEther("95")    // minBondingTokens (5% slippage)
);
```

#### removeLiquidity

```solidity
function removeLiquidity(uint256 bondingTokenAmount, uint256 minInputTokens)
    external
    nonReentrant
    returns (uint256 inputTokensOut)
```

Removes liquidity from the pool by burning bonding tokens with optional withdrawal fee.

**Prerequisites:**
- User must own sufficient bonding tokens
- Contract must not be locked

**Parameters:**
- `bondingTokenAmount`: Amount of bonding tokens to burn (full amount including fee portion)
- `minInputTokens`: Minimum input tokens expected (slippage protection, net amount after fee)

**Returns:**
- `inputTokensOut`: Actual input tokens received (net amount after fee deduction)

**Fee Mechanism:**
- Optional withdrawal fee applied based on `withdrawalFeeBasisPoints` (0-10000)
- Fee calculation: `feeAmount = (bondingTokenAmount * withdrawalFeeBasisPoints) / 10000`
- Effective amount: `effectiveAmount = bondingTokenAmount - feeAmount`
- Full `bondingTokenAmount` is burned from user (deflationary)
- Output calculated only on `effectiveAmount`, not full amount
- Fee is permanently removed from circulation

**Events Emitted:**
- `LiquidityRemoved(user, bondingTokenAmount, inputTokensOut)`
- `FeeCollected(user, bondingTokenAmount, feeAmount)` (if fee > 0)

### Quote Functions

#### quoteAddLiquidity

```solidity
function quoteAddLiquidity(uint256 inputAmount)
    external
    view
    returns (uint256 bondingTokensOut)
```

Calculates bonding tokens that would be received for a given input amount.

**Parameters:**
- `inputAmount`: Amount of input tokens to simulate

**Returns:**
- `bondingTokensOut`: Bonding tokens that would be minted

#### quoteRemoveLiquidity

```solidity
function quoteRemoveLiquidity(uint256 bondingTokenAmount)
    external
    view
    returns (uint256 inputTokensOut)
```

Calculates input tokens that would be received for burning bonding tokens (after fee deduction).

**Parameters:**
- `bondingTokenAmount`: Amount of bonding tokens to simulate burning (full amount)

**Returns:**
- `inputTokensOut`: Input tokens that would be returned (net amount after fee deduction)

**Fee Impact:**
- Quote automatically accounts for current `withdrawalFeeBasisPoints`
- Returns actual amount user would receive, not gross amount
- Use this for accurate slippage calculations and UI display
- Calculation mirrors exact logic used in `removeLiquidity()`

### Price Functions

#### getCurrentMarginalPrice

```solidity
function getCurrentMarginalPrice() external view returns (uint256 price)
```

Returns the current marginal price (derivative of the bonding curve).

**Returns:**
- `price`: Current marginal price in wei (18 decimals)

#### getAveragePrice

```solidity
function getAveragePrice() external view returns (uint256 avgPrice)
```

Returns the average price from the start to current state.

**Returns:**
- `avgPrice`: Average price in wei (18 decimals)

#### getInitialMarginalPrice

```solidity
function getInitialMarginalPrice() external view returns (uint256 initialPrice)
```

Returns the initial marginal price when virtual liquidity was set.

**Returns:**
- `initialPrice`: Initial marginal price in wei (18 decimals)

#### getFinalMarginalPrice

```solidity
function getFinalMarginalPrice() external pure returns (uint256 finalPrice)
```

Returns the final marginal price when funding goal is reached.

**Returns:**
- `finalPrice`: Always returns 1e18 (1.0 in 18 decimals)

### State Query Functions

#### getTotalRaised

```solidity
function getTotalRaised() public view returns (uint256 totalRaised)
```

Returns the total amount of input tokens raised since launch start.

**Zero Seed Behavior:**
- Returns current `virtualInputTokens` amount
- Starts at 0 due to zero seed enforcement
- Increases as users add liquidity

**Returns:**
- `totalRaised`: Total input tokens deposited (starts at 0 with zero seed)

#### getVirtualPair

```solidity
function getVirtualPair() external view returns (uint256 inputTokens, uint256 lTokens, uint256 k)
```

Returns the current virtual pair state for the offset bonding curve.

**Zero Seed Behavior:**
- `inputTokens` starts at 0 and increases as liquidity is added
- Uses (x+α)(y+β)=k formula, not simple xy=k
- `k` represents the virtual constant product, not inputTokens × lTokens

**Returns:**
- `inputTokens`: Current virtual input token amount (starts at 0)
- `lTokens`: Current virtual L token amount (calculated as k/α - α initially)
- `k`: Virtual constant product for (x+α)(y+β)=k formula

#### isVirtualPairInitialized

```solidity
function isVirtualPairInitialized() external view returns (bool)
```

Checks if virtual liquidity parameters have been set.

**Returns:**
- `bool`: True if virtual pair is initialized

## Owner Functions

### Configuration

#### setGoals

```solidity
function setGoals(uint256 _fundingGoal, uint256 _desiredAveragePrice) external onlyOwner
```

Sets the virtual liquidity parameters for the launch with **zero seed enforcement**.

**Zero Seed Enforcement:**
- Seed input is automatically set to 0 (cannot be configured)
- Virtual input tokens start at 0 (fair launch guarantee)
- Initial price calculated as P₀ = P_avg²

**Parameters:**
- `_fundingGoal`: Target amount of input tokens to raise (must be > 0)
- `_desiredAveragePrice`: Target average price scaled by 1e18
  - Must be ≥ 866025403784438647 (√0.75) to ensure P₀ ≥ 0.75
  - Must be < 1e18 (< 1.0) to prevent overflow

**Mathematical Calculations:**
- **Alpha (α)**: `(P_avg × funding_goal) / (1 - P_avg)`
- **Beta (β)**: `α` (equal to alpha)
- **Virtual K**: `(funding_goal + α)²`
- **Initial Virtual L**: `k/α - α`
- **Initial Price**: `P_avg²`

**Events Emitted:**
- `VirtualLiquidityGoalsSet(fundingGoal, 0, desiredAveragePrice, alpha, beta, virtualK)`

**Example:**
```javascript
// Set goals for 1M token funding with 0.88 average price
// This creates P₀ = 0.7744 (77.44% initial price)
await tokenLaunch.setGoals(
    ethers.parseEther("1000000"),  // 1M funding goal
    ethers.parseEther("0.88")      // 0.88 average price → 0.7744 initial price
);
```

#### setInputToken

```solidity
function setInputToken(address _token) external onlyOwner
```

Updates the input token address.

**Parameters:**
- `_token`: New input token contract address

#### setVault

```solidity
function setVault(address _vault) external onlyOwner
```

Updates the vault contract address.

**Parameters:**
- `_vault`: New vault contract address

**Events Emitted:**
- `VaultChanged(oldVault, newVault)`

### Vault Management

#### initializeVaultApproval

```solidity
function initializeVaultApproval() external onlyOwner
```

Initializes maximum approval for the vault to optimize gas usage.

**Prerequisites:**
- Vault must have authorized this contract: `vault.setClient(address(this), true)`

#### disableToken

```solidity
function disableToken() external onlyOwner
```

Emergency function to revoke vault approval for the input token.

### Access Control

#### lock

```solidity
function lock() external onlyOwner
```

Locks the contract to prevent all operations.

**Events Emitted:**
- `ContractLocked()`

#### unlock

```solidity
function unlock() external onlyOwner
```

Unlocks the contract to resume operations.

**Events Emitted:**
- `ContractUnlocked()`

#### setAutoLock

```solidity
function setAutoLock(bool _autoLock) external onlyOwner
```

Configures automatic locking when funding goal is reached.

**Parameters:**
- `_autoLock`: Whether to enable auto-lock functionality

#### setWithdrawalFee

```solidity
function setWithdrawalFee(uint256 _feeBasisPoints) external onlyOwner
```

Sets the withdrawal fee for `removeLiquidity` operations.

**Parameters:**
- `_feeBasisPoints`: Fee in basis points (0-10000), where 10000 = 100%

**Fee Examples:**
- `0` = 0% (no fee)
- `50` = 0.5%
- `100` = 1%
- `250` = 2.5%
- `500` = 5%
- `1000` = 10%
- `2500` = 25%
- `10000` = 100% (maximum)

**Behavior:**
- Fee is applied during `removeLiquidity()` calls
- Full `bondingTokenAmount` is burned from user supply
- Only effective amount (after fee deduction) used for withdrawal calculation
- Fee is permanently removed from circulation (deflationary mechanism)
- Changes are immediately effective for new withdrawal operations

**Events Emitted:**
- `WithdrawalFeeUpdated(oldFee, newFee)`

## Events

### LiquidityAdded
```solidity
event LiquidityAdded(address indexed user, uint256 inputAmount, uint256 bondingTokensOut)
```

Emitted when liquidity is added to the pool.

### LiquidityRemoved
```solidity
event LiquidityRemoved(address indexed user, uint256 bondingTokenAmount, uint256 inputTokensOut)
```

Emitted when liquidity is removed from the pool.

### ContractLocked
```solidity
event ContractLocked()
```

Emitted when the contract is locked.

### ContractUnlocked
```solidity
event ContractUnlocked()
```

Emitted when the contract is unlocked.

### VaultChanged
```solidity
event VaultChanged(address indexed oldVault, address indexed newVault)
```

Emitted when the vault address is updated.

### WithdrawalFeeUpdated
```solidity
event WithdrawalFeeUpdated(uint256 oldFee, uint256 newFee)
```

Emitted when the withdrawal fee is updated via `setWithdrawalFee()`.

### FeeCollected
```solidity
event FeeCollected(address indexed user, uint256 bondingTokenAmount, uint256 feeAmount)
```

Emitted when a withdrawal fee is collected during `removeLiquidity()` operations. Only emitted when `feeAmount > 0`.

### VirtualLiquidityGoalsSet
```solidity
event VirtualLiquidityGoalsSet(
    uint256 fundingGoal,
    uint256 seedInput,
    uint256 desiredAveragePrice,
    uint256 virtualInputTokens,
    uint256 virtualL,
    uint256 alpha,
    uint256 beta
)
```

Emitted when virtual liquidity parameters are configured.

## Error Conditions

### Common Errors

- **"Contract is locked"**: Operations attempted while contract is locked
- **"Insufficient input tokens out"**: Slippage protection triggered on remove liquidity
- **"Insufficient bonding tokens out"**: Slippage protection triggered on add liquidity
- **"Transfer failed"**: ERC20 transfer failed (check approval and balance)
- **"Vault approval not initialized"**: Must call `initializeVaultApproval()` first

### Approval-Related Errors

Since this contract uses standard ERC20 patterns without permit functionality:

- **"ERC20: insufficient allowance"**: User hasn't approved enough tokens
- **"ERC20: transfer amount exceeds balance"**: User doesn't have enough tokens

## Integration Examples

### Basic Integration

```javascript
// 1. Deploy contracts
const inputToken = await InputToken.deploy();
const bondingToken = await BondingToken.deploy();
const vault = await Vault.deploy();
const tokenLaunch = await TokenLaunch.deploy(
    inputToken.address,
    bondingToken.address,
    vault.address
);

// 2. Configure vault
await vault.setClient(tokenLaunch.address, true);
await tokenLaunch.initializeVaultApproval();

// 3. Set launch parameters with zero seed enforcement
await tokenLaunch.setGoals(
    ethers.parseEther("1000000"), // 1M funding goal
    ethers.parseEther("0.9")      // 0.9 average price → P₀ = 0.81
);

// 4. User adds liquidity
await inputToken.connect(user).approve(
    tokenLaunch.address,
    ethers.parseEther("100")
);
await tokenLaunch.connect(user).addLiquidity(
    ethers.parseEther("100"),
    ethers.parseEther("95") // 5% slippage tolerance
);
```

### Frontend Integration

```javascript
class TokenLaunchInterface {
    constructor(web3, contractAddress, abi) {
        this.contract = new web3.eth.Contract(abi, contractAddress);
        this.web3 = web3;
    }

    async addLiquidity(userAddress, inputAmount, slippageTolerance = 0.05) {
        // 1. Check current quote
        const quote = await this.contract.methods
            .quoteAddLiquidity(inputAmount)
            .call();

        // 2. Calculate minimum with slippage
        const minBondingTokens = quote * (1 - slippageTolerance);

        // 3. Check and approve if needed
        const inputToken = new this.web3.eth.Contract(
            ERC20_ABI,
            await this.contract.methods.inputToken().call()
        );

        const allowance = await inputToken.methods
            .allowance(userAddress, this.contract.options.address)
            .call();

        if (allowance < inputAmount) {
            await inputToken.methods
                .approve(this.contract.options.address, inputAmount)
                .send({ from: userAddress });
        }

        // 4. Add liquidity
        return await this.contract.methods
            .addLiquidity(inputAmount, minBondingTokens)
            .send({ from: userAddress });
    }
}
```

## Security Considerations

### Standard ERC20 Patterns Only

- **No Permit Support**: Contract does not implement EIP-2612 permit functionality
- **Explicit Approvals Required**: Users must call `approve()` before `addLiquidity()`
- **Enhanced Security**: Simplified approval flow reduces attack surface
- **Compatibility**: Works with all standard ERC20 tokens without additional requirements

### Access Control

- Owner functions protected by `onlyOwner` modifier
- Critical functions protected by reentrancy guard
- Emergency lock functionality available

### Slippage Protection

- Both `addLiquidity` and `removeLiquidity` include slippage protection
- Users specify minimum expected output amounts
- Transactions revert if slippage exceeds tolerance

## Gas Optimization

### Deferred Vault Approval

- Constructor doesn't perform vault approval to prevent deployment failures
- Owner calls `initializeVaultApproval()` after vault authorization
- Uses maximum approval to save ~5000 gas per `addLiquidity` call

### Optimized Calculations

- DRY principle implementation eliminates code duplication
- Shared calculation functions between quote and execution
- Efficient virtual pair mathematics

## Migration from Permit-Based Versions

If migrating from a version that supported permit functionality:

1. **Update Frontend**: Remove permit signature generation code
2. **Add Approval Step**: Implement standard ERC20 approval flow
3. **Update Integration**: Replace permit calls with approve/transfer pattern
4. **Test Thoroughly**: Verify all operations work with new approval flow

See the full migration guide in `docs/permit-removal-migration-guide.md` for detailed instructions.