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

```bash
# Configure platform parameters (if applicable)
# Example: Setting fees, limits, or other configurable parameters
cast send $TOKEN_LAUNCH_ADDRESS "setParameter(uint256)" 100 \
    --rpc-url $RPC_URL --private-key $OWNER_PRIVATE_KEY

# Transfer ownership (if needed)
cast send $TOKEN_LAUNCH_ADDRESS "transferOwnership(address)" $NEW_OWNER_ADDRESS \
    --rpc-url $RPC_URL --private-key $CURRENT_OWNER_PRIVATE_KEY
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
event Transfer(address indexed from, address indexed to, uint256 value);
event Approval(address indexed owner, address indexed spender, uint256 value);
event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
// Additional custom events specific to TokenLaunch functionality
```

#### Example Monitoring Script

```javascript
// Using ethers.js or web3.js
const tokenLaunch = new ethers.Contract(TOKEN_LAUNCH_ADDRESS, abi, provider);

// Monitor transfers
tokenLaunch.on("Transfer", (from, to, value, event) => {
    console.log(`Transfer: ${from} -> ${to}, Amount: ${value}`);
});

// Monitor approvals
tokenLaunch.on("Approval", (owner, spender, value, event) => {
    console.log(`Approval: ${owner} approved ${spender} for ${value}`);
});
```

### Step 10: Regular Maintenance Tasks

#### Parameter Review

- Monitor penalty effectiveness through transaction data
- Adjust parameters based on user behavior and market conditions
- Review gas costs for timestamp operations

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
