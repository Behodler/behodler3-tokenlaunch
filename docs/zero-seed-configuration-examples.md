# Zero Seed Virtual Liquidity Configuration Examples

## Overview

This document provides practical configuration examples for zero seed virtual liquidity launches. Each example demonstrates how different `P_avg` values create specific initial prices and bonding curve characteristics.

## Key Relationship: P₀ = P_avg²

With zero seed enforcement, the initial price is always the square of the desired average price:

```
Initial Price (P₀) = (Average Price)²
```

This creates predictable and fair pricing from the start of each token launch.

## Configuration Examples

### Example 1: Moderate Initial Price (P_avg = 0.88)

**Configuration:**
```javascript
const fundingGoal = ethers.parseEther("1000000"); // 1M tokens
const averagePrice = ethers.parseEther("0.88");   // 88% average price

await tokenLaunch.setGoals(fundingGoal, averagePrice);
```

**Results:**
- **Initial Price (P₀)**: 0.88² = 0.7744 (77.44%)
- **Final Price**: 1.0 (100%)
- **Price Range**: 77.44% → 100% (22.56% price appreciation)

**Calculated Parameters:**
- **Alpha (α)**: (0.88 × 1,000,000) / (1 - 0.88) = 7,333,333.33 tokens
- **Beta (β)**: 7,333,333.33 tokens (equals alpha)
- **Virtual K**: (1,000,000 + 7,333,333.33)² ≈ 6.944 × 10¹³
- **Initial Virtual L**: k/α - α ≈ 947,368,421 tokens

**Use Case**: Moderate initial pricing suitable for established projects wanting balanced early/late participant pricing.

### Example 2: Lower Initial Price (P_avg = 0.90)

**Configuration:**
```javascript
const fundingGoal = ethers.parseEther("500000");  // 500K tokens
const averagePrice = ethers.parseEther("0.90");   // 90% average price

await tokenLaunch.setGoals(fundingGoal, averagePrice);
```

**Results:**
- **Initial Price (P₀)**: 0.90² = 0.81 (81%)
- **Final Price**: 1.0 (100%)
- **Price Range**: 81% → 100% (19% price appreciation)

**Calculated Parameters:**
- **Alpha (α)**: (0.90 × 500,000) / (1 - 0.90) = 4,500,000 tokens
- **Beta (β)**: 4,500,000 tokens
- **Virtual K**: (500,000 + 4,500,000)² = 2.5 × 10¹³
- **Initial Virtual L**: k/α - α = 1,055,555.56 tokens

**Use Case**: Higher initial pricing for premium projects or when targeting smaller price appreciation ranges.

### Example 3: Minimum Valid Configuration (P_avg = √0.75)

**Configuration:**
```javascript
const fundingGoal = ethers.parseEther("2000000"); // 2M tokens
const averagePrice = "866025403784438647";         // √0.75 (minimum valid)

await tokenLaunch.setGoals(fundingGoal, averagePrice);
```

**Results:**
- **Initial Price (P₀)**: (√0.75)² = 0.75 (exactly 75%)
- **Final Price**: 1.0 (100%)
- **Price Range**: 75% → 100% (25% price appreciation)

**Calculated Parameters:**
- **Alpha (α)**: (√0.75 × 2,000,000) / (1 - √0.75) ≈ 12,928,203.23 tokens
- **Beta (β)**: 12,928,203.23 tokens
- **Virtual K**: (2,000,000 + 12,928,203.23)² ≈ 2.226 × 10¹⁴
- **Initial Virtual L**: k/α - α ≈ 4,303,433.88 tokens

**Use Case**: Maximum price appreciation scenario, suitable for early-stage projects wanting significant upward price movement.

### Example 4: High Initial Price (P_avg = 0.95)

**Configuration:**
```javascript
const fundingGoal = ethers.parseEther("100000");  // 100K tokens
const averagePrice = ethers.parseEther("0.95");   // 95% average price

await tokenLaunch.setGoals(fundingGoal, averagePrice);
```

**Results:**
- **Initial Price (P₀)**: 0.95² = 0.9025 (90.25%)
- **Final Price**: 1.0 (100%)
- **Price Range**: 90.25% → 100% (9.75% price appreciation)

**Calculated Parameters:**
- **Alpha (α)**: (0.95 × 100,000) / (1 - 0.95) = 1,900,000 tokens
- **Beta (β)**: 1,900,000 tokens
- **Virtual K**: (100,000 + 1,900,000)² = 4 × 10¹²
- **Initial Virtual L**: k/α - α = 205,263.16 tokens

**Use Case**: Minimal price movement for stable pricing scenarios or when targeting professional investors.

### Example 5: Large Scale Launch (P_avg = 0.875)

**Configuration:**
```javascript
const fundingGoal = ethers.parseEther("10000000"); // 10M tokens
const averagePrice = ethers.parseEther("0.875");   // 87.5% average price

await tokenLaunch.setGoals(fundingGoal, averagePrice);
```

**Results:**
- **Initial Price (P₀)**: 0.875² = 0.765625 (76.5625%)
- **Final Price**: 1.0 (100%)
- **Price Range**: 76.56% → 100% (23.44% price appreciation)

**Calculated Parameters:**
- **Alpha (α)**: (0.875 × 10,000,000) / (1 - 0.875) = 70,000,000 tokens
- **Beta (β)**: 70,000,000 tokens
- **Virtual K**: (10,000,000 + 70,000,000)² = 6.4 × 10¹⁵
- **Initial Virtual L**: k/α - α = 21,428,571.43 tokens

**Use Case**: Large-scale institutional launches with balanced pricing incentives.

## Step-by-Step Setup Guide

### 1. Choose Your Parameters

Consider these factors when selecting `P_avg`:
- **Target initial price** (P₀ = P_avg²)
- **Desired price appreciation** (100% - P₀)
- **Early participant incentives** (lower P_avg = more incentive)
- **Project maturity** (established projects can use higher P_avg)

### 2. Calculate Expected Results

Use this formula to predict outcomes:
```
Initial Price = P_avg²
Price Appreciation = (1.0 - P_avg²) × 100%
Alpha = (P_avg × funding_goal) / (1 - P_avg)
```

### 3. Deploy and Configure

```javascript
// 1. Deploy contracts
const tokenLaunch = await TokenLaunch.deploy(inputToken, bondingToken, vault);

// 2. Setup vault authorization
await vault.setClient(tokenLaunch.address, true);
await tokenLaunch.initializeVaultApproval();

// 3. Set goals with chosen parameters
await tokenLaunch.setGoals(
    ethers.parseEther(fundingGoalString),
    ethers.parseEther(averagePriceString)
);

// 4. Verify configuration
const totalRaised = await tokenLaunch.getTotalRaised();
const initialPrice = await tokenLaunch.getInitialMarginalPrice();
const currentPrice = await tokenLaunch.getCurrentMarginalPrice();

console.log(`Total Raised: ${totalRaised} (should be 0 with zero seed)`);
console.log(`Initial Price: ${initialPrice}`);
console.log(`Current Price: ${currentPrice} (should equal initial price)`);
```

### 4. Test the Configuration

```javascript
// Test a small purchase to verify pricing
const testAmount = ethers.parseEther("1000");
const quote = await tokenLaunch.quoteAddLiquidity(testAmount);
console.log(`1000 tokens would yield ${quote} bonding tokens`);

// Verify price bounds
const finalPrice = await tokenLaunch.getFinalMarginalPrice();
console.log(`Final price will be: ${finalPrice} (should be 1e18)`);
```

## Configuration Decision Matrix

| Project Stage | Recommended P_avg | Initial Price (P₀) | Price Appreciation | Use Case |
|---------------|-------------------|--------------------|--------------------|----------|
| Early Stage   | 0.866 - 0.88     | 75% - 77.44%      | 25% - 22.56%      | Maximum growth incentive |
| Growth Stage  | 0.88 - 0.92       | 77.44% - 84.64%   | 22.56% - 15.36%   | Balanced incentives |
| Mature        | 0.92 - 0.95       | 84.64% - 90.25%   | 15.36% - 9.75%    | Stable pricing |
| Institutional | 0.95 - 0.98       | 90.25% - 96.04%   | 9.75% - 3.96%     | Minimal volatility |

## Common Pitfalls to Avoid

### 1. P_avg Too Low
- **Problem**: P_avg < √0.75 causes transaction to revert
- **Solution**: Always use P_avg ≥ 0.866025403784438647

### 2. P_avg = 1.0
- **Problem**: Creates division by zero in alpha calculation
- **Solution**: Keep P_avg < 1.0 (recommended max: 0.985)

### 3. Unrealistic Funding Goals
- **Problem**: Very large funding goals with high P_avg can cause overflow
- **Solution**: Test calculations with your specific parameters

### 4. Misunderstanding Price Formula
- **Problem**: Expecting initial price to equal P_avg
- **Solution**: Remember P₀ = P_avg², not P₀ = P_avg

## Validation Checklist

Before launching, verify:
- [ ] P_avg ≥ 0.866025403784438647 (√0.75)
- [ ] P_avg < 1.0
- [ ] Funding goal > 0
- [ ] Initial price = P_avg² as expected
- [ ] Alpha calculation doesn't overflow
- [ ] Total raised starts at 0
- [ ] Virtual input tokens start at 0
- [ ] Contract is properly initialized

## Advanced Scenarios

### Dynamic P_avg Selection

For projects wanting to optimize based on market conditions:

```javascript
function calculateOptimalPAvg(
    targetInitialPricePercent,
    marketVolatility
) {
    // Target initial price as decimal (e.g., 0.80 for 80%)
    const targetP0 = targetInitialPricePercent;

    // Calculate required P_avg: P_avg = √P₀
    const requiredPAvg = Math.sqrt(targetP0);

    // Adjust for market volatility (higher volatility = lower P_avg)
    const volatilityAdjustment = 1 - (marketVolatility * 0.1);
    const adjustedPAvg = requiredPAvg * volatilityAdjustment;

    // Ensure within valid bounds
    const minPAvg = Math.sqrt(0.75);
    const maxPAvg = 0.985;

    return Math.max(minPAvg, Math.min(maxPAvg, adjustedPAvg));
}

// Example: Target 78% initial price with medium volatility
const optimalPAvg = calculateOptimalPAvg(0.78, 0.5);
console.log(`Optimal P_avg: ${optimalPAvg}`); // Approximately 0.838
```

### Multi-Stage Launch Planning

For projects planning multiple funding rounds:

```javascript
// Stage 1: Early supporters (lower price, higher appreciation)
const stage1Config = {
    fundingGoal: ethers.parseEther("500000"),
    averagePrice: ethers.parseEther("0.87") // P₀ = 0.7569
};

// Stage 2: Growth round (moderate pricing)
const stage2Config = {
    fundingGoal: ethers.parseEther("1000000"),
    averagePrice: ethers.parseEther("0.91") // P₀ = 0.8281
};

// Stage 3: Final round (stable pricing)
const stage3Config = {
    fundingGoal: ethers.parseEther("2000000"),
    averagePrice: ethers.parseEther("0.94") // P₀ = 0.8836
};
```

This approach provides progressively higher initial prices for later participants while maintaining fairness within each stage.