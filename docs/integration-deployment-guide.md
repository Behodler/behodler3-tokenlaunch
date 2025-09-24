# Behodler3 TokenLaunch Integration and Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Behodler3 TokenLaunch platform. The platform provides a simplified architecture using standard ERC20 approve/transfer patterns without EIP-2612 permit functionality for enhanced security and compatibility.

## Prerequisites

### Required Contracts

- `Behodler3Tokenlaunch.sol` - Main platform contract with simplified architecture
- Hook contracts (optional) - For configurable trading behaviors

### Development Environment

- Foundry framework
- OpenZeppelin contracts (^4.8.0)
- Solidity ^0.8.13
- Valid RPC endpoint for target network

### Access Requirements

- Contract owner/admin privileges for TokenLaunch platform
- Sufficient gas for deployment transactions
- Network-specific deployment configuration

## Deployment Process

### Step 1: Contract Compilation

```bash
# Ensure all dependencies are installed
forge install

# Compile contracts
forge build

# Run tests to verify implementation
forge test --match-contract EarlySellPenaltyHookTest
```

Expected output should show all tests passing with no compilation errors.

### Step 2: Deploy Behodler3Tokenlaunch Contract

#### Using Forge Script (Recommended)

The deployment script is located at `script/Deploy.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Behodler3Tokenlaunch.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the TokenLaunch contract
        Behodler3Tokenlaunch tokenLaunch = new Behodler3Tokenlaunch();

        console.log("Behodler3Tokenlaunch deployed to:", address(tokenLaunch));
        console.log("Owner:", tokenLaunch.owner());
        console.log("Contract deployed without permit functionality");

        vm.stopBroadcast();
    }
}
```

Deploy using:

```bash
# Set environment variables
export PRIVATE_KEY=0x... # Your deployer private key
export RPC_URL=https://... # Your RPC endpoint

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify

# Deploy to mainnet (add --legacy if needed)
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify --legacy
```

#### Manual Deployment via Forge Create

```bash
# Deploy contract directly
forge create src/Behodler3Tokenlaunch.sol:Behodler3Tokenlaunch \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify

# Example response:
# Deployed to: 0x1234...5678
# Transaction hash: 0xabcd...ef01
```

### Step 3: Verify Contract Deployment

After deployment, verify the contract is properly initialized:

```bash
# Using cast to check deployment
export TOKEN_LAUNCH_ADDRESS=0x... # Address from deployment

# Verify owner
cast call $TOKEN_LAUNCH_ADDRESS "owner()" --rpc-url $RPC_URL
# Expected: Your deployer address

# Verify contract state
cast call $TOKEN_LAUNCH_ADDRESS "totalSupply()" --rpc-url $RPC_URL
# Should show current total supply

# Test basic functionality (read-only)
cast call $TOKEN_LAUNCH_ADDRESS "name()" --rpc-url $RPC_URL
cast call $TOKEN_LAUNCH_ADDRESS "symbol()" --rpc-url $RPC_URL
```

## Platform Configuration

### Step 4: Basic Configuration

The TokenLaunch platform uses standard ERC20 patterns without permit functionality:

- Users interact with the contract using standard `approve()` and `transferFrom()` functions
- No permit signatures are required or supported
- Enhanced security through simplified approval mechanisms

#### Usage Patterns

Standard ERC20 interaction patterns:

```bash
# Approve tokens for spending (if needed)
cast send $TOKEN_ADDRESS "approve(address,uint256)" $TOKEN_LAUNCH_ADDRESS 1000000000000000000 \
    --rpc-url $RPC_URL --private-key $USER_PRIVATE_KEY

# Check allowance
cast call $TOKEN_ADDRESS "allowance(address,address)" $USER_ADDRESS $TOKEN_LAUNCH_ADDRESS \
    --rpc-url $RPC_URL

# Interact with TokenLaunch contract
cast send $TOKEN_LAUNCH_ADDRESS "buy(uint256)" 1000000000000000000 \
    --rpc-url $RPC_URL --private-key $USER_PRIVATE_KEY --value 0.1ether
```

### Step 5: Verify Deployment

Confirm the contract is deployed and functional:

```bash
# Test basic functionality
cast call $TOKEN_LAUNCH_ADDRESS "name()" --rpc-url $RPC_URL
cast call $TOKEN_LAUNCH_ADDRESS "symbol()" --rpc-url $RPC_URL
cast call $TOKEN_LAUNCH_ADDRESS "decimals()" --rpc-url $RPC_URL

# Verify ownership and access controls
cast call $TOKEN_LAUNCH_ADDRESS "owner()" --rpc-url $RPC_URL
```

## Post-Deployment Configuration

### Step 6: Owner Functions

Configure the TokenLaunch contract after deployment:

#### Virtual Liquidity Goals Configuration

Set the funding parameters for the token launch:

```bash
# Set funding goal and desired average price (required before operations)
# Example: 1,000,000 tokens funding goal with 0.9 average price (90%)
cast send $TOKEN_LAUNCH_ADDRESS "setGoals(uint256,uint256)" \
    1000000000000000000000000 900000000000000000 \
    --rpc-url $RPC_URL --private-key $OWNER_PRIVATE_KEY
```

#### Withdrawal Fee Configuration

Configure optional withdrawal fees for removeLiquidity operations:

```bash
# Set withdrawal fee (0-10000 basis points, where 10000 = 100%)
# Example: 250 basis points = 2.5% withdrawal fee
cast send $TOKEN_LAUNCH_ADDRESS "setWithdrawalFee(uint256)" 250 \
    --rpc-url $RPC_URL --private-key $OWNER_PRIVATE_KEY

# Check current withdrawal fee
cast call $TOKEN_LAUNCH_ADDRESS "withdrawalFeeBasisPoints()" --rpc-url $RPC_URL

# Remove withdrawal fee (set to 0)
cast send $TOKEN_LAUNCH_ADDRESS "setWithdrawalFee(uint256)" 0 \
    --rpc-url $RPC_URL --private-key $OWNER_PRIVATE_KEY
```

**Fee Examples:**
- `0` = 0% (no fee)
- `50` = 0.5%
- `100` = 1%
- `250` = 2.5%
- `500` = 5%
- `1000` = 10%
- `2500` = 25%

#### Vault Approval Initialization

Initialize vault approval after vault authorization:

```bash
# First: Authorize this contract in the vault (run on vault contract)
cast send $VAULT_ADDRESS "setClient(address,bool)" $TOKEN_LAUNCH_ADDRESS true \
    --rpc-url $RPC_URL --private-key $VAULT_OWNER_PRIVATE_KEY

# Then: Initialize vault approval in TokenLaunch contract
cast send $TOKEN_LAUNCH_ADDRESS "initializeVaultApproval()" \
    --rpc-url $RPC_URL --private-key $OWNER_PRIVATE_KEY
```

#### Access Control Management

```bash
# Transfer ownership (if needed)
cast send $TOKEN_LAUNCH_ADDRESS "transferOwnership(address)" $NEW_OWNER_ADDRESS \
    --rpc-url $RPC_URL --private-key $CURRENT_OWNER_PRIVATE_KEY

# Verify new ownership
cast call $TOKEN_LAUNCH_ADDRESS "owner()" --rpc-url $RPC_URL
```

### Step 7: Emergency Controls

Access emergency functionality if implemented:

```bash
# Pause contract operations (if pause functionality exists)
cast send $TOKEN_LAUNCH_ADDRESS "pause()" \
    --rpc-url $RPC_URL --private-key $OWNER_PRIVATE_KEY

# Unpause contract operations
cast send $TOKEN_LAUNCH_ADDRESS "unpause()" \
    --rpc-url $RPC_URL --private-key $OWNER_PRIVATE_KEY
```

## Post-Deployment Verification

### Step 8: End-to-End Testing

Perform comprehensive testing to ensure the contract works correctly:

#### Test Buy Operation

```bash
# Simulate buy transaction
cast send $TOKEN_LAUNCH_ADDRESS "buy(uint256)" 1000000000000000000 \
    --rpc-url $RPC_URL --private-key $TEST_USER_PRIVATE_KEY --value 0.1ether

# Verify transaction success
cast receipt $BUY_TX_HASH --rpc-url $RPC_URL
```

#### Test Standard ERC20 Operations

```bash
# Check token balance after purchase
cast call $TOKEN_LAUNCH_ADDRESS "balanceOf(address)" $TEST_USER_ADDRESS --rpc-url $RPC_URL

# Test standard approve/transfer pattern
cast send $TOKEN_LAUNCH_ADDRESS "approve(address,uint256)" $SPENDER_ADDRESS 1000000 \
    --rpc-url $RPC_URL --private-key $TEST_USER_PRIVATE_KEY

# Check allowance
cast call $TOKEN_LAUNCH_ADDRESS "allowance(address,address)" $TEST_USER_ADDRESS $SPENDER_ADDRESS \
    --rpc-url $RPC_URL
```

#### Test Sell Operation

```bash
# Simulate sell transaction
cast send $TOKEN_LAUNCH_ADDRESS "sell(uint256)" 500000000000000000 \
    --rpc-url $RPC_URL --private-key $TEST_USER_PRIVATE_KEY

# Verify transaction success and events
cast receipt $SELL_TX_HASH --rpc-url $RPC_URL
```

## Monitoring and Maintenance

### Step 9: Event Monitoring Setup

Monitor contract events for operational insights:

#### Key Events to Track

```solidity
// Liquidity Operations
event LiquidityAdded(address indexed user, uint256 inputAmount, uint256 bondingTokensOut);
event LiquidityRemoved(address indexed user, uint256 bondingTokenAmount, uint256 inputTokensOut);

// Fee-Related Events
event WithdrawalFeeUpdated(uint256 oldFee, uint256 newFee);
event FeeCollected(address indexed user, uint256 bondingTokenAmount, uint256 feeAmount);

// System Events
event ContractLocked();
event ContractUnlocked();
event VaultChanged(address indexed oldVault, address indexed newVault);
event VirtualLiquidityGoalsSet(uint256 fundingGoal, uint256 seedInput, uint256 desiredAveragePrice, uint256 alpha, uint256 beta, uint256 virtualK);

// Standard ERC20 Events
event Transfer(address indexed from, address indexed to, uint256 value);
event Approval(address indexed owner, address indexed spender, uint256 value);
event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
```

#### Example Monitoring Script

```javascript
// Using ethers.js or web3.js
const tokenLaunch = new ethers.Contract(TOKEN_LAUNCH_ADDRESS, abi, provider);

// Monitor liquidity operations
tokenLaunch.on("LiquidityAdded", (user, inputAmount, bondingTokensOut, event) => {
    console.log(`Liquidity Added: User ${user}, Input: ${ethers.utils.formatEther(inputAmount)}, Bonding Tokens: ${ethers.utils.formatEther(bondingTokensOut)}`);
});

tokenLaunch.on("LiquidityRemoved", (user, bondingTokenAmount, inputTokensOut, event) => {
    console.log(`Liquidity Removed: User ${user}, Bonding Tokens: ${ethers.utils.formatEther(bondingTokenAmount)}, Input Tokens: ${ethers.utils.formatEther(inputTokensOut)}`);
});

// Monitor fee-related events
tokenLaunch.on("WithdrawalFeeUpdated", (oldFee, newFee, event) => {
    console.log(`Withdrawal Fee Updated: ${oldFee} basis points -> ${newFee} basis points`);
});

tokenLaunch.on("FeeCollected", (user, bondingTokenAmount, feeAmount, event) => {
    const feePercentage = (feeAmount * 10000n) / bondingTokenAmount;
    console.log(`Fee Collected: User ${user}, Fee: ${ethers.utils.formatEther(feeAmount)} (${feePercentage} basis points)`);
});

// Monitor system events
tokenLaunch.on("ContractLocked", (event) => {
    console.log("Contract has been locked");
});

tokenLaunch.on("ContractUnlocked", (event) => {
    console.log("Contract has been unlocked");
});

// Monitor configuration changes
tokenLaunch.on("VirtualLiquidityGoalsSet", (fundingGoal, seedInput, desiredAveragePrice, alpha, beta, virtualK, event) => {
    console.log(`Virtual Liquidity Goals Set: Funding Goal: ${ethers.utils.formatEther(fundingGoal)}, Average Price: ${ethers.utils.formatEther(desiredAveragePrice)}`);
});
```

### Step 10: Regular Maintenance Tasks

#### Parameter Review

**Withdrawal Fee Management:**
- Monitor fee collection effectiveness through `FeeCollected` events
- Analyze user behavior impact from different fee levels
- Adjust withdrawal fees based on market conditions and project needs
- Review deflationary impact on bonding token supply

**Virtual Liquidity Parameters:**
- Monitor funding progress toward goals
- Review price curve behavior and user adoption
- Consider parameter adjustments based on market feedback

**Gas Cost Analysis:**
- Track gas costs for liquidity operations with fees
- Monitor fee calculation overhead (~475 gas maximum)
- Optimize monitoring scripts for efficient event processing

#### Security Monitoring

- Watch for unusual timestamp patterns
- Monitor for potential gaming attempts
- Verify owner access controls remain secure

#### Performance Optimization

- Track gas consumption for buy/sell operations
- Monitor storage growth of buyer timestamp mappings
- Consider cleanup mechanisms for inactive addresses

## Troubleshooting

### Common Issues and Solutions

#### Hook Not Called During Transactions

**Problem**: Buy/sell operations don't trigger hook functions
**Solution**:

1. Verify hook is properly set in TokenLaunch contract
2. Check TokenLaunch implementation calls hook during buy/sell
3. Ensure hook address is correct and contract is deployed

#### Penalty Calculations Incorrect

**Problem**: Penalty amounts don't match expected values
**Solution**:

1. Check current block timestamp vs. buyer timestamp
2. Verify penalty parameters are set correctly
3. Test penalty calculation function directly

#### Permission Errors

**Problem**: Cannot modify penalty parameters
**Solution**:

1. Verify caller is contract owner
2. Check owner address is set correctly after deployment
3. Use correct private key for owner transactions

#### Gas Issues

**Problem**: Transactions failing due to gas limits
**Solution**:

1. Increase gas limit for complex transactions
2. Consider gas optimization if storage operations are expensive
3. Monitor gas usage patterns over time

## Summary

The Behodler3 TokenLaunch deployment process involves:

1. **Deployment**: Deploy the TokenLaunch contract with proper verification
2. **Configuration**: Set up owner permissions and basic parameters
3. **Verification**: Test end-to-end functionality with buy/sell operations
4. **Monitoring**: Set up event monitoring for operational oversight
5. **Maintenance**: Regular performance monitoring and security updates

This simplified system provides enhanced security through the removal of permit functionality, using standard ERC20 approve/transfer patterns that are well-tested and secure.

## Additional Resources

- **Contract Documentation**: See `src/Behodler3Tokenlaunch.sol` for complete implementation
- **Test Examples**: Review `test/` directory for testing patterns and integration examples
- **Gas Analysis**: See `docs/gas-analysis.md` for detailed cost breakdowns
- **Performance Tuning**: See `docs/PERFORMANCE-TUNING.md` for optimization guidance

For additional support or custom configurations, refer to the main TokenLaunch documentation or contact the development team.
