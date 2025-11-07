# Emergency Pause Procedure

## Overview

The Behodler3Tokenlaunch contract includes an emergency pause mechanism that allows anyone to pause the contract by burning EYE tokens. This provides a decentralized emergency response system while preventing griefing through a significant cost barrier.

## Architecture

The pause system consists of two components:

### 1. Pauser Contract (`Pauser.sol`)
- **Purpose**: Manages the pause mechanism with EYE token burning requirement
- **Owner**: Deployer/Admin
- **Public Functions**:
  - `pause()`: Anyone can call this to pause Behodler by burning EYE tokens
- **Owner Functions**:
  - `unpause()`: Unpause the Behodler contract
  - `config(uint256 _eyeBurnAmount, address _behodlerContract)`: Configure burn amount and target contract

### 2. Behodler3Tokenlaunch Contract (`Behodler3Tokenlaunch.sol`)
- **Inherits**: OpenZeppelin Pausable
- **Paused Functions**: `addLiquidity()`, `removeLiquidity()`
- **Pause Control**: Only Pauser contract can trigger pause
- **Unpause Control**: Owner or Pauser contract can unpause

## How to Trigger Emergency Pause

### Prerequisites
- Have sufficient EYE tokens (default: 1000 EYE)
- Approve Pauser contract to spend your EYE tokens

### Steps

1. **Approve EYE Token Spending**
   ```solidity
   // Approve Pauser to spend EYE tokens
   eyeToken.approve(pauserAddress, requiredBurnAmount);
   ```

2. **Trigger Pause**
   ```solidity
   // Call pause function on Pauser contract
   pauser.pause();
   ```

3. **Verification**
   ```solidity
   // Verify contract is paused
   bool isPaused = behodler.paused(); // Should return true
   ```

### What Happens When Paused

- `pause()` function burns the required amount of EYE tokens from caller
- Pauser contract calls `Behodler3Tokenlaunch.pause()`
- The following functions become blocked:
  - `addLiquidity()` - Cannot add new liquidity
  - `removeLiquidity()` - Cannot remove liquidity
- All other view/query functions remain operational

## How to Unpause

### Only owner can unpause the contract

**Option 1: Via Pauser Contract (Recommended)**
```solidity
// Owner calls unpause on Pauser contract
pauser.unpause();
```

**Option 2: Direct Call to Behodler**
```solidity
// Owner calls unpause directly on Behodler contract
behodler.unpause();
```

## Configuration

### Initial Deployment

The Pauser contract is deployed with the following default configuration:
- **EYE Burn Amount**: 1000 EYE (1000 * 10^18 wei)
- **Behodler Contract**: Set during deployment via `config()`

### Updating Configuration

Only the owner can update the configuration:

```solidity
// Update burn amount and/or Behodler address
pauser.config(newBurnAmount, newBehodlerAddress);
```

**Example: Reduce burn amount to 500 EYE**
```solidity
pauser.config(500 * 1e18, behodlerAddress);
```

## Security Considerations

### Cost Barrier
- The EYE burning requirement prevents frivolous pause attempts
- Default 1000 EYE creates significant economic cost
- Tokens are burned (sent to 0xdead), not sent to any party

### Access Control
- **Pause**: Anyone can pause (with EYE burn cost)
- **Unpause**: Only owner or Pauser contract
- **Configuration**: Only Pauser owner

### Edge Cases

1. **Insufficient EYE Balance**
   - Transaction will revert if caller doesn't have enough EYE
   - Ensure approval amount matches burn amount

2. **Already Paused**
   - Attempting to pause when already paused will revert
   - EYE tokens will not be burned in this case

3. **Not Paused**
   - Attempting to unpause when not paused will revert

## Emergency Response Workflow

### Detection Phase
1. Vulnerability or exploit discovered
2. Community member or team identifies the issue
3. Decision made that pause is necessary

### Execution Phase
1. Responder acquires required EYE tokens
2. Approves Pauser contract for spending
3. Calls `pauser.pause()` function
4. EYE tokens are burned, contract pauses
5. Verification that pause is active

### Resolution Phase
1. Team analyzes the issue
2. Fix is developed and tested
3. Fix is deployed (if contract upgrade needed) or issue is resolved
4. Owner calls `pauser.unpause()` to restore operations
5. Verification that contract is operational

## Testing

Comprehensive test coverage includes:
- Pause mechanism with EYE burning
- Access control for pause/unpause
- Blocking of operations when paused
- Resumption of operations after unpause
- Edge cases and security scenarios

Run tests:
```bash
forge test --match-contract PauserTest -vv
```

## Contract Addresses

Update after deployment:
- **Pauser Contract**: `<TO_BE_DEPLOYED>`
- **Behodler3Tokenlaunch Contract**: `<TO_BE_DEPLOYED>`
- **EYE Token**: `<EXISTING_ADDRESS>`

## Events

The contracts emit the following events for monitoring:

### Pauser Events
- `PauseTriggered(address indexed triggeredBy, uint256 eyeBurned)`
- `UnpauseTriggered(address indexed triggeredBy)`
- `ConfigUpdated(uint256 newEyeBurnAmount, address newBehodlerContract)`

### Behodler3Tokenlaunch Events
- `Paused(address account)` (OpenZeppelin Pausable)
- `Unpaused(address account)` (OpenZeppelin Pausable)
- `PauserUpdated(address indexed oldPauser, address indexed newPauser)`

## Support

For questions or issues related to the pause mechanism:
1. Review this documentation
2. Check test files for implementation examples
3. Consult with development team
