# Early Sell Penalty Calculation Formula

## Overview

The EarlySellPenaltyHook implements a time-based penalty mechanism that discourages early selling by applying declining fees based on the time elapsed since the last purchase.

## Mathematical Formula

The penalty calculation uses an exponential decay model based on hourly intervals:

### Core Formula
```
penaltyFee = max(0, 1000 - (hoursElapsed × penaltyDeclineRatePerHour))
```

Where:
- `penaltyFee`: Final penalty in basis points (0-1000, where 1000 = 100%)
- `hoursElapsed`: Complete hours since last buy transaction
- `penaltyDeclineRatePerHour`: Decline rate per hour (default: 10, representing 1%)
- `1000`: Maximum penalty (100%) applied at time 0

### Time Calculation
```
hoursElapsed = (block.timestamp - buyerLastBuyTimestamp) / 3600
```

Where:
- `block.timestamp`: Current block timestamp in seconds
- `buyerLastBuyTimestamp`: Timestamp of buyer's last purchase
- `3600`: Seconds per hour for conversion

## Default Parameters

- **Initial Penalty**: 100% (1000 basis points)
- **Decline Rate**: 1% per hour (10 basis points)
- **Maximum Duration**: 100 hours
- **Final Penalty**: 0% after 100 hours

## Example Calculations

### Scenario: 1000 Token Sale at Different Time Intervals

Assuming a user purchases tokens and then attempts to sell 1000 tokens at various intervals:

#### Immediate Sale (0 hours)
```
hoursElapsed = 0
penaltyFee = 1000 - (0 × 10) = 1000 (100%)
effectiveTokensReceived = 1000 × (1000 - 1000) / 1000 = 0 tokens
```

#### 1 Hour After Purchase
```
hoursElapsed = 1
penaltyFee = 1000 - (1 × 10) = 990 (99%)
effectiveTokensReceived = 1000 × (1000 - 990) / 1000 = 10 tokens
```

#### 12 Hours After Purchase
```
hoursElapsed = 12
penaltyFee = 1000 - (12 × 10) = 880 (88%)
effectiveTokensReceived = 1000 × (1000 - 880) / 1000 = 120 tokens
```

#### 24 Hours After Purchase
```
hoursElapsed = 24
penaltyFee = 1000 - (24 × 10) = 760 (76%)
effectiveTokensReceived = 1000 × (1000 - 760) / 1000 = 240 tokens
```

#### 48 Hours After Purchase
```
hoursElapsed = 48
penaltyFee = 1000 - (48 × 10) = 520 (52%)
effectiveTokensReceived = 1000 × (1000 - 520) / 1000 = 480 tokens
```

#### 96 Hours After Purchase
```
hoursElapsed = 96
penaltyFee = 1000 - (96 × 10) = 40 (4%)
effectiveTokensReceived = 1000 × (1000 - 40) / 1000 = 960 tokens
```

#### 100+ Hours After Purchase
```
hoursElapsed = 100
penaltyFee = max(0, 1000 - (100 × 10)) = 0 (0%)
effectiveTokensReceived = 1000 × (1000 - 0) / 1000 = 1000 tokens
```

## Edge Cases

### First-Time Sellers
Users who sell without any previous buy transactions receive the maximum penalty (100%):
```
if (buyerLastBuyTimestamp[seller] == 0) {
    penaltyFee = 1000;
}
```

### Timestamp Reset
Each new buy operation resets the timestamp, restarting the penalty countdown:
```
// On new buy
buyerLastBuyTimestamp[buyer] = block.timestamp;
```

### Time Manipulation Protection
The contract handles potential edge cases where `block.timestamp` might be less than `lastBuyTimestamp`:
```
if (block.timestamp < lastBuyTimestamp) {
    hoursElapsed = 0;
}
```

### Parameter Validation
The contract enforces mathematical consistency:
```
require(penaltyDeclineRatePerHour * maxPenaltyDurationHours >= 1000, 
    "Parameters must allow penalty to reach 0");
```

## Penalty Progression Graph

The penalty follows a linear decay pattern:

```
Penalty %
    100 |*
     90 | *
     80 |  *
     70 |   *
     60 |    *
     50 |     *
     40 |      *
     30 |       *
     20 |        *
     10 |         *
      0 |__________*___________> Time (hours)
        0  10  20  30 ... 100
```

## Gas Efficiency Notes

- Timestamp storage: Single SSTORE operation per buy
- Penalty calculation: Pure view function using simple arithmetic
- No loops or complex operations in critical path
- Storage reads only for timestamp retrieval

## Customization Options

Contract owners can modify the decay parameters:
- `penaltyDeclineRatePerHour`: Adjust how quickly penalty decreases
- `maxPenaltyDurationHours`: Set the duration until penalty reaches zero
- `penaltyActive`: Emergency pause functionality

The formula remains the same, but different parameters create different penalty curves suitable for various token economics strategies.