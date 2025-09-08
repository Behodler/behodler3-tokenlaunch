# Early Sell Penalty Usage Examples

## Overview

This document provides concrete examples of how the EarlySellPenaltyHook affects token sales at different time intervals, demonstrating the practical impact of the penalty mechanism on trading behavior.

## Scenario Setup

**Context**: User purchases tokens through the TokenLaunch platform and then attempts to sell different amounts at various time intervals.

**Default Parameters**:
- Initial penalty: 100%
- Decline rate: 1% per hour
- Maximum penalty duration: 96 hours (penalty reaches 0%)
- Penalty unit: Basis points (1000 = 100%)

## Example 1: Complete Sale of 1000 Tokens

### Timeline and Penalties

| Time Elapsed | Hours | Penalty % | Penalty (BP) | Tokens Received | Tokens Lost to Penalty |
|--------------|-------|-----------|--------------|-----------------|----------------------|
| Immediate    | 0     | 100%      | 1000         | 0               | 1000                 |
| 1 hour       | 1     | 99%       | 990          | 10              | 990                  |
| 6 hours      | 6     | 94%       | 940          | 60              | 940                  |
| 12 hours     | 12    | 88%       | 880          | 120             | 880                  |
| 24 hours     | 24    | 76%       | 760          | 240             | 760                  |
| 48 hours     | 48    | 52%       | 520          | 480             | 520                  |
| 72 hours     | 72    | 28%       | 280          | 720             | 280                  |
| 96 hours     | 96    | 4%        | 40           | 960             | 40                   |
| 100+ hours   | 100   | 0%        | 0            | 1000            | 0                    |

### Detailed Calculations

#### 1 Hour After Purchase
```solidity
hoursElapsed = (block.timestamp - lastBuyTimestamp) / 3600 = 1
penaltyFee = 1000 - (1 × 10) = 990 basis points
effectiveReceived = 1000 × (1000 - 990) / 1000 = 10 tokens
penaltyAmount = 1000 × 990 / 1000 = 990 tokens
```

#### 12 Hours After Purchase
```solidity
hoursElapsed = 12
penaltyFee = 1000 - (12 × 10) = 880 basis points
effectiveReceived = 1000 × (1000 - 880) / 1000 = 120 tokens
penaltyAmount = 1000 × 880 / 1000 = 880 tokens
```

#### 24 Hours After Purchase
```solidity
hoursElapsed = 24
penaltyFee = 1000 - (24 × 10) = 760 basis points
effectiveReceived = 1000 × (1000 - 760) / 1000 = 240 tokens
penaltyAmount = 1000 × 760 / 1000 = 760 tokens
```

#### 48 Hours After Purchase
```solidity
hoursElapsed = 48
penaltyFee = 1000 - (48 × 10) = 520 basis points
effectiveReceived = 1000 × (1000 - 520) / 1000 = 480 tokens
penaltyAmount = 1000 × 520 / 1000 = 520 tokens
```

#### 96 Hours After Purchase
```solidity
hoursElapsed = 96
penaltyFee = 1000 - (96 × 10) = 40 basis points
effectiveReceived = 1000 × (1000 - 40) / 1000 = 960 tokens
penaltyAmount = 1000 × 40 / 1000 = 40 tokens
```

## Example 2: Partial Sales Strategy

A user purchases 5000 tokens and sells in smaller batches over time:

### Strategy: Sell 1000 tokens every 24 hours

| Sale # | Time | Hours Elapsed | Penalty % | Tokens Sold | Tokens Received | Cumulative Received |
|--------|------|---------------|-----------|-------------|-----------------|-------------------|
| 1      | Day 1| 24            | 76%       | 1000        | 240             | 240               |
| 2      | Day 2| 48            | 52%       | 1000        | 480             | 720               |
| 3      | Day 3| 72            | 28%       | 1000        | 720             | 1440              |
| 4      | Day 4| 96            | 4%        | 1000        | 960             | 2400              |
| 5      | Day 5| 120           | 0%        | 1000        | 1000            | 3400              |

**Total Tokens Sold**: 5000  
**Total Tokens Received**: 3400  
**Total Penalty Paid**: 1600 tokens

### Strategy: Wait 96 hours, then sell all

| Sale # | Time | Hours Elapsed | Penalty % | Tokens Sold | Tokens Received |
|--------|------|---------------|-----------|-------------|-----------------|
| 1      | Day 4| 96            | 4%        | 5000        | 4800            |

**Total Tokens Sold**: 5000  
**Total Tokens Received**: 4800  
**Total Penalty Paid**: 200 tokens

**Analysis**: Waiting strategy yields 1400 more tokens (4800 vs 3400)

## Example 3: Multiple Buy/Sell Cycles

### Scenario: Timestamp Reset Behavior

User demonstrates how new purchases reset the penalty timer:

#### Transaction 1: Initial Purchase
- **Action**: Buy 2000 tokens
- **Timestamp**: T₀
- **Effect**: `buyerLastBuyTimestamp[user] = T₀`

#### Transaction 2: First Sale Attempt (6 hours later)
- **Time**: T₀ + 6 hours
- **Action**: Sell 1000 tokens
- **Penalty**: 94% (940 basis points)
- **Received**: 60 tokens

#### Transaction 3: Additional Purchase (12 hours after initial)
- **Time**: T₀ + 12 hours
- **Action**: Buy 1000 more tokens
- **Effect**: `buyerLastBuyTimestamp[user] = T₀ + 12 hours` (RESET)

#### Transaction 4: Second Sale Attempt (18 hours after initial, 6 hours after second buy)
- **Time**: T₀ + 18 hours
- **Hours Since Last Buy**: 6 hours (not 18!)
- **Action**: Sell 1500 tokens
- **Penalty**: 94% (940 basis points)
- **Received**: 90 tokens

**Key Learning**: The timestamp reset means penalty is always calculated from the most recent buy, not the original purchase.

## Example 4: First-Time Seller Edge Case

### Scenario: User receives tokens without buying

User receives 500 tokens through airdrop or transfer and attempts to sell:

```solidity
// User's buyerLastBuyTimestamp = 0 (never bought)
function calculatePenaltyFee(address seller) returns (uint256) {
    if (buyerLastBuyTimestamp[seller] == 0) {
        return 1000; // Maximum penalty
    }
    // ... rest of calculation
}
```

**Result**: 
- Penalty: 100% (1000 basis points)
- Tokens received: 0
- Tokens lost to penalty: 500

**Rationale**: Prevents gaming the system by acquiring tokens through non-purchase means to avoid penalties.

## Example 5: Different Penalty Parameters

Contract owner adjusts parameters for different economics:

### Conservative Setting (Longer Holding Period)
- `penaltyDeclineRatePerHour = 5` (0.5% per hour)
- `maxPenaltyDurationHours = 200`

| Time | Penalty % | 1000 Tokens Sale Result |
|------|-----------|------------------------|
| 1h   | 99.5%     | 5 tokens              |
| 24h  | 88%       | 120 tokens            |
| 48h  | 76%       | 240 tokens            |
| 96h  | 52%       | 480 tokens            |
| 200h | 0%        | 1000 tokens           |

### Aggressive Setting (Shorter Holding Period)  
- `penaltyDeclineRatePerHour = 20` (2% per hour)
- `maxPenaltyDurationHours = 50`

| Time | Penalty % | 1000 Tokens Sale Result |
|------|-----------|------------------------|
| 1h   | 98%       | 20 tokens             |
| 12h  | 76%       | 240 tokens            |
| 24h  | 52%       | 480 tokens            |
| 48h  | 4%        | 960 tokens            |
| 50h  | 0%        | 1000 tokens           |

## Example 6: Emergency Pause Scenario

### Before Pause
```solidity
penaltyActive = true;
// Sale of 1000 tokens after 24 hours: 240 tokens received
```

### After Owner Pauses
```solidity
function setPenaltyActive(false) external onlyOwner;
penaltyActive = false;
// Sale of 1000 tokens after 24 hours: 1000 tokens received
```

**Use Case**: Emergency situations, contract upgrades, or temporary market interventions.

## Practical Implementation Examples

### Frontend Integration
```javascript
// Calculate expected penalty for user
async function calculateSalePenalty(userAddress, saleAmount) {
    const lastBuyTimestamp = await penaltyHook.getBuyerTimestamp(userAddress);
    const currentTimestamp = Math.floor(Date.now() / 1000);
    
    if (lastBuyTimestamp === 0) {
        return { penalty: saleAmount, received: 0, penaltyPercent: 100 };
    }
    
    const hoursElapsed = Math.floor((currentTimestamp - lastBuyTimestamp) / 3600);
    const penaltyFee = Math.max(0, 1000 - (hoursElapsed * 10));
    const penaltyAmount = (saleAmount * penaltyFee) / 1000;
    const receivedAmount = saleAmount - penaltyAmount;
    
    return {
        penalty: penaltyAmount,
        received: receivedAmount,
        penaltyPercent: penaltyFee / 10
    };
}
```

### Time-Based UI Warnings
```javascript
// Show user when penalty will decrease
function getNextPenaltyReduction(lastBuyTimestamp) {
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const hoursElapsed = Math.floor((currentTimestamp - lastBuyTimestamp) / 3600);
    const nextHour = (hoursElapsed + 1) * 3600;
    const nextReductionTime = lastBuyTimestamp + nextHour;
    
    return {
        currentPenalty: Math.max(0, 100 - hoursElapsed),
        nextPenalty: Math.max(0, 100 - (hoursElapsed + 1)),
        nextReductionTime: new Date(nextReductionTime * 1000),
        timeToNextReduction: nextReductionTime - currentTimestamp
    };
}
```

## Summary

The EarlySellPenaltyHook creates strong incentives for holding tokens while maintaining liquidity options. The examples demonstrate:

1. **Immediate sales are heavily penalized** (100% penalty)
2. **Patience is rewarded** with significantly more tokens received
3. **Timestamp resets** prevent gaming through multiple small purchases
4. **First-time sellers** cannot bypass the penalty system
5. **Parameter flexibility** allows for different economic models
6. **Emergency controls** provide administrative oversight

This mechanism effectively discourages short-term speculation while preserving long-term liquidity for committed holders.