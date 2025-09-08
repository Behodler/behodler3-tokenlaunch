# EarlySellPenaltyHook Integration and Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying and integrating the EarlySellPenaltyHook with the Behodler3 TokenLaunch platform. The hook system allows for configurable penalties to discourage early selling while maintaining system flexibility.

## Prerequisites

### Required Contracts
- `Behodler3Tokenlaunch.sol` - Main platform contract (from stories 004-005)
- `IEarlySellPenaltyHook.sol` - Hook interface
- `EarlySellPenaltyHook.sol` - Penalty implementation
- `IBondingCurveHook.sol` - Base hook interface

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

### Step 2: Deploy EarlySellPenaltyHook Contract

#### Using Forge Script (Recommended)

Create deployment script `script/DeployPenaltyHook.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/EarlySellPenaltyHook.sol";

contract DeployPenaltyHook is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the penalty hook contract
        EarlySellPenaltyHook penaltyHook = new EarlySellPenaltyHook();
        
        console.log("EarlySellPenaltyHook deployed to:", address(penaltyHook));
        console.log("Default parameters:");
        console.log("- Decline rate per hour:", penaltyHook.penaltyDeclineRatePerHour());
        console.log("- Max penalty duration:", penaltyHook.maxPenaltyDurationHours());
        console.log("- Penalty active:", penaltyHook.penaltyActive());
        
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
forge script script/DeployPenaltyHook.s.sol --rpc-url $RPC_URL --broadcast --verify

# Deploy to mainnet (add --legacy if needed)
forge script script/DeployPenaltyHook.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify --legacy
```

#### Manual Deployment via Forge Create

```bash
# Deploy contract directly
forge create src/EarlySellPenaltyHook.sol:EarlySellPenaltyHook \
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
export PENALTY_HOOK_ADDRESS=0x... # Address from deployment

# Verify default parameters
cast call $PENALTY_HOOK_ADDRESS "penaltyDeclineRatePerHour()" --rpc-url $RPC_URL
# Expected: 10 (representing 1% per hour)

cast call $PENALTY_HOOK_ADDRESS "maxPenaltyDurationHours()" --rpc-url $RPC_URL
# Expected: 100

cast call $PENALTY_HOOK_ADDRESS "penaltyActive()" --rpc-url $RPC_URL
# Expected: true

# Verify owner
cast call $PENALTY_HOOK_ADDRESS "owner()" --rpc-url $RPC_URL
# Expected: Your deployer address
```

## Integration with TokenLaunch Platform

### Step 4: Connect Hook to TokenLaunch Contract

The TokenLaunch platform includes a `setHook()` function from the configurable hook system (story 005):

```solidity
function setHook(IBondingCurveHook _hook) external onlyOwner {
    hook = _hook;
    emit HookSet(address(_hook));
}
```

#### Integration Script

Create integration script `script/IntegratePenaltyHook.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IBondingCurveHook.sol";

interface ITokenLaunch {
    function setHook(IBondingCurveHook _hook) external;
    function hook() external view returns (IBondingCurveHook);
    function owner() external view returns (address);
}

contract IntegratePenaltyHook is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PLATFORM_OWNER_PRIVATE_KEY");
        address tokenLaunchAddress = vm.envAddress("TOKEN_LAUNCH_ADDRESS");
        address penaltyHookAddress = vm.envAddress("PENALTY_HOOK_ADDRESS");
        
        vm.startBroadcast(ownerPrivateKey);
        
        ITokenLaunch tokenLaunch = ITokenLaunch(tokenLaunchAddress);
        IBondingCurveHook penaltyHook = IBondingCurveHook(penaltyHookAddress);
        
        // Set the penalty hook
        tokenLaunch.setHook(penaltyHook);
        
        // Verify integration
        IBondingCurveHook currentHook = tokenLaunch.hook();
        require(address(currentHook) == penaltyHookAddress, "Hook integration failed");
        
        console.log("Successfully integrated penalty hook:");
        console.log("- TokenLaunch:", tokenLaunchAddress);
        console.log("- PenaltyHook:", penaltyHookAddress);
        console.log("- Current hook:", address(currentHook));
        
        vm.stopBroadcast();
    }
}
```

Execute integration:
```bash
# Set integration environment variables
export PLATFORM_OWNER_PRIVATE_KEY=0x... # TokenLaunch owner key
export TOKEN_LAUNCH_ADDRESS=0x... # TokenLaunch contract address
export PENALTY_HOOK_ADDRESS=0x... # Deployed penalty hook address

# Run integration
forge script script/IntegratePenaltyHook.s.sol --rpc-url $RPC_URL --broadcast
```

### Step 5: Verify Integration

Confirm the hook is properly connected and functional:

```bash
# Check hook is set in TokenLaunch
cast call $TOKEN_LAUNCH_ADDRESS "hook()" --rpc-url $RPC_URL
# Should return: PENALTY_HOOK_ADDRESS

# Test hook functionality with a read-only call
cast call $PENALTY_HOOK_ADDRESS "calculatePenaltyFee(address)" $TEST_ADDRESS --rpc-url $RPC_URL
# Should return penalty amount (1000 for first-time seller)
```

## Configuration and Customization

### Step 6: Adjust Penalty Parameters (Optional)

Customize the penalty mechanism for your specific tokenomics:

#### Standard Configuration (Default)
- **Decline rate**: 1% per hour (10 basis points)
- **Maximum duration**: 100 hours
- **Initial penalty**: 100%

#### Conservative Configuration (Longer holding incentive)
```bash
# Set more gradual decline (0.5% per hour, 200 hours total)
cast send $PENALTY_HOOK_ADDRESS "setPenaltyParameters(uint256,uint256)" 5 200 \
    --rpc-url $RPC_URL --private-key $HOOK_OWNER_PRIVATE_KEY
```

#### Aggressive Configuration (Shorter holding requirement)
```bash
# Set faster decline (2% per hour, 50 hours total)
cast send $PENALTY_HOOK_ADDRESS "setPenaltyParameters(uint256,uint256)" 20 50 \
    --rpc-url $RPC_URL --private-key $HOOK_OWNER_PRIVATE_KEY
```

#### Parameter Validation
The contract automatically validates parameters:
```solidity
require(declineRate * maxDuration >= 1000, "Parameters must allow penalty to reach 0");
```

### Step 7: Emergency Controls Setup

Configure emergency pause functionality:

```bash
# Pause penalty application (emergency)
cast send $PENALTY_HOOK_ADDRESS "setPenaltyActive(bool)" false \
    --rpc-url $RPC_URL --private-key $HOOK_OWNER_PRIVATE_KEY

# Re-enable penalty application
cast send $PENALTY_HOOK_ADDRESS "setPenaltyActive(bool)" true \
    --rpc-url $RPC_URL --private-key $HOOK_OWNER_PRIVATE_KEY
```

## Post-Deployment Verification

### Step 8: End-to-End Testing

Perform comprehensive testing to ensure the integration works correctly:

#### Test Buy Operation
```bash
# Simulate buy transaction (should record timestamp)
# This will trigger the penalty hook's buy() function
cast send $TOKEN_LAUNCH_ADDRESS "buy(uint256)" 1000000000000000000 \
    --rpc-url $RPC_URL --private-key $TEST_USER_PRIVATE_KEY --value 0.1ether
```

#### Verify Timestamp Recording
```bash
# Check that buyer timestamp was recorded
cast call $PENALTY_HOOK_ADDRESS "getBuyerTimestamp(address)" $TEST_USER_ADDRESS --rpc-url $RPC_URL
# Should return recent timestamp (block.timestamp from buy transaction)
```

#### Test Sell Operation
```bash
# Simulate sell transaction (should apply penalty)
cast send $TOKEN_LAUNCH_ADDRESS "sell(uint256)" 500000000000000000 \
    --rpc-url $RPC_URL --private-key $TEST_USER_PRIVATE_KEY
```

#### Verify Penalty Application
Check transaction logs for `PenaltyApplied` events:
```bash
# Get recent transaction receipt
cast receipt $SELL_TX_HASH --rpc-url $RPC_URL
# Look for PenaltyApplied(address seller, uint256 fee, uint256 hoursElapsed) events
```

## Monitoring and Maintenance

### Step 9: Event Monitoring Setup

Monitor hook events for operational insights:

#### Key Events to Track
```solidity
event BuyerTimestampRecorded(address indexed buyer, uint256 timestamp);
event PenaltyApplied(address indexed seller, uint256 fee, uint256 hoursElapsed);
event PenaltyParametersUpdated(uint256 declineRatePerHour, uint256 maxDurationHours);
event PenaltyStatusChanged(bool active);
```

#### Example Monitoring Script
```javascript
// Using ethers.js or web3.js
const penaltyHook = new ethers.Contract(PENALTY_HOOK_ADDRESS, abi, provider);

// Monitor penalty applications
penaltyHook.on("PenaltyApplied", (seller, fee, hoursElapsed, event) => {
    console.log(`Penalty applied: ${seller}, Fee: ${fee/10}%, Hours: ${hoursElapsed}`);
});

// Monitor timestamp recordings
penaltyHook.on("BuyerTimestampRecorded", (buyer, timestamp, event) => {
    console.log(`Timestamp recorded: ${buyer}, Time: ${new Date(timestamp * 1000)}`);
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

The EarlySellPenaltyHook integration process involves:

1. **Deployment**: Deploy the penalty hook contract with proper verification
2. **Integration**: Connect the hook to the TokenLaunch platform using `setHook()`
3. **Configuration**: Adjust penalty parameters for desired tokenomics
4. **Verification**: Test end-to-end functionality with buy/sell operations
5. **Monitoring**: Set up event monitoring for operational oversight
6. **Maintenance**: Regular parameter review and performance monitoring

This system provides a flexible, configurable penalty mechanism that can be adapted to various token launch scenarios while maintaining administrative control and emergency response capabilities.

## Additional Resources

- **Interface Documentation**: See `IEarlySellPenaltyHook.sol` for complete function signatures
- **Test Examples**: Review `test/EarlySellPenaltyHookTest.sol` for integration patterns
- **Parameter Calculator**: Use the penalty calculation formula to model different configurations
- **Gas Analysis**: See `gas-analysis.md` for detailed cost breakdowns

For additional support or custom configurations, refer to the main TokenLaunch documentation or contact the development team.