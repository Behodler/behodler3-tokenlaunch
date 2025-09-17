**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary

- [incorrect-exp](#incorrect-exp) (1 results) (High)
- [divide-before-multiply](#divide-before-multiply) (10 results) (Medium)
- [incorrect-equality](#incorrect-equality) (4 results) (Medium)
- [reentrancy-no-eth](#reentrancy-no-eth) (5 results) (Medium)
- [shadowing-local](#shadowing-local) (6 results) (Low)
- [missing-zero-check](#missing-zero-check) (8 results) (Low)
- [reentrancy-events](#reentrancy-events) (1 results) (Low)
- [timestamp](#timestamp) (7 results) (Low)
- [assembly](#assembly) (29 results) (Informational)
- [pragma](#pragma) (1 results) (Informational)
- [cyclomatic-complexity](#cyclomatic-complexity) (2 results) (Informational)
- [solc-version](#solc-version) (5 results) (Informational)
- [missing-inheritance](#missing-inheritance) (2 results) (Informational)
- [naming-convention](#naming-convention) (31 results) (Informational)
- [too-many-digits](#too-many-digits) (2 results) (Informational)
- [unused-state](#unused-state) (1 results) (Informational)
- [immutable-states](#immutable-states) (2 results) (Optimization)

## incorrect-exp

Impact: High
Confidence: Medium

- [ ] ID-0
      [Math.mulDiv(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) has bitwise-xor operator ^ instead of the exponentiation operator \*_: - [inverse = (3 _ denominator) ^ 2](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L257)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275

## divide-before-multiply

Impact: Medium
Confidence: Medium

- [ ] ID-1
      [Math.mulDiv(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division: - [denominator = denominator / twos](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242) - [inverse = (3 \* denominator) ^ 2](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L257)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275

- [ ] ID-2
      [MockEarlySellPenaltyHook.calculatePenaltyFee(address)](src/mocks/MockEarlySellPenaltyHook.sol#L104-L126) performs a multiplication on the result of a division: - [hoursElapsed = timeElapsed / 3600](src/mocks/MockEarlySellPenaltyHook.sol#L115) - [penalty = 1000 - (hoursElapsed \* penaltyDeclineRatePerHour)](src/mocks/MockEarlySellPenaltyHook.sol#L122)

src/mocks/MockEarlySellPenaltyHook.sol#L104-L126

- [ ] ID-3
      [Math.mulDiv(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division: - [denominator = denominator / twos](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242) - [inverse _= 2 - denominator _ inverse](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L264)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275

- [ ] ID-4
      [Math.invMod(uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L315-L361) performs a multiplication on the result of a division: - [quotient = gcd / remainder](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L337) - [(gcd,remainder) = (remainder,gcd - remainder \* quotient)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L339-L346)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L315-L361

- [ ] ID-5
      [Math.mulDiv(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division: - [denominator = denominator / twos](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242) - [inverse _= 2 - denominator _ inverse](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L263)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275

- [ ] ID-6
      [Math.mulDiv(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division: - [denominator = denominator / twos](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242) - [inverse _= 2 - denominator _ inverse](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L262)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275

- [ ] ID-7
      [Math.mulDiv(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division: - [denominator = denominator / twos](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242) - [inverse _= 2 - denominator _ inverse](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L266)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275

- [ ] ID-8
      [Math.mulDiv(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division: - [denominator = denominator / twos](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242) - [inverse _= 2 - denominator _ inverse](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L265)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275

- [ ] ID-9
      [Math.mulDiv(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division: - [denominator = denominator / twos](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242) - [inverse _= 2 - denominator _ inverse](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L261)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275

- [ ] ID-10
      [Math.mulDiv(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division: - [low = low / twos](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L245) - [result = low \* inverse](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L272)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275

## incorrect-equality

Impact: Medium
Confidence: High

- [ ] ID-11
      [EarlySellPenaltyHook.\_getHoursElapsed(address)](src/EarlySellPenaltyHook.sol#L204-L221) uses a dangerous strict equality: - [lastBuyTimestamp == 0](src/EarlySellPenaltyHook.sol#L210)

src/EarlySellPenaltyHook.sol#L204-L221

- [ ] ID-12
      [MockEarlySellPenaltyHook.getHoursElapsed(address)](src/mocks/MockEarlySellPenaltyHook.sol#L129-L135) uses a dangerous strict equality: - [lastBuyTimestamp == 0](src/mocks/MockEarlySellPenaltyHook.sol#L131)

src/mocks/MockEarlySellPenaltyHook.sol#L129-L135

- [ ] ID-13
      [MockEarlySellPenaltyHook.calculatePenaltyFee(address)](src/mocks/MockEarlySellPenaltyHook.sol#L104-L126) uses a dangerous strict equality: - [lastBuyTimestamp == 0](src/mocks/MockEarlySellPenaltyHook.sol#L108)

src/mocks/MockEarlySellPenaltyHook.sol#L104-L126

- [ ] ID-14
      [EarlySellPenaltyHook.calculatePenaltyFee(address)](src/EarlySellPenaltyHook.sol#L132-L168) uses a dangerous strict equality: - [lastBuyTimestamp == 0](src/EarlySellPenaltyHook.sol#L145)

src/EarlySellPenaltyHook.sol#L132-L168

## reentrancy-no-eth

Impact: Medium
Confidence: Medium

- [ ] ID-15
      Reentrancy in [Behodler3Tokenlaunch.disableToken()](src/Behodler3Tokenlaunch.sol#L487-L494):
      External calls: - [! inputToken.approve(address(vault),0)](src/Behodler3Tokenlaunch.sol#L491)
      State variables written after the call(s): - [vaultApprovalInitialized = false](src/Behodler3Tokenlaunch.sol#L493)
      [Behodler3Tokenlaunch.vaultApprovalInitialized](src/Behodler3Tokenlaunch.sol#L141) can be used in cross function reentrancies: - [Behodler3Tokenlaunch.\_setInputToken(IERC20)](src/Behodler3Tokenlaunch.sol#L459-L467) - [Behodler3Tokenlaunch.\_setVault(IVault)](src/Behodler3Tokenlaunch.sol#L510-L519) - [Behodler3Tokenlaunch.constructor(IERC20,IBondingToken,IVault)](src/Behodler3Tokenlaunch.sol#L213-L228) - [Behodler3Tokenlaunch.disableToken()](src/Behodler3Tokenlaunch.sol#L487-L494) - [Behodler3Tokenlaunch.initializeVaultApproval()](src/Behodler3Tokenlaunch.sol#L474-L481) - [Behodler3Tokenlaunch.vaultApprovalInitialized](src/Behodler3Tokenlaunch.sol#L141)

src/Behodler3Tokenlaunch.sol#L487-L494

- [ ] ID-16
      Reentrancy in [Behodler3Tokenlaunch.removeLiquidity(uint256,uint256)](src/Behodler3Tokenlaunch.sol#L633-L708):
      External calls: - [(hookFee,deltaBondingToken) = \_bondingCurveHook.sell(msg.sender,bondingTokenAmount,baseInputTokens)](src/Behodler3Tokenlaunch.sol#L649-L653) - [bondingToken.burn(msg.sender,bondingTokenAmount)](src/Behodler3Tokenlaunch.sol#L694) - [vault.withdraw(address(inputToken),inputTokensOut,address(this))](src/Behodler3Tokenlaunch.sol#L698) - [! inputToken.transfer(msg.sender,inputTokensOut)](src/Behodler3Tokenlaunch.sol#L699)
      State variables written after the call(s): - [\_updateVirtualLiquidityState(- int256(baseInputTokens),int256(bondingTokenAmount))](src/Behodler3Tokenlaunch.sol#L703) - [virtualInputTokens += uint256(inputTokenDelta)](src/Behodler3Tokenlaunch.sol#L435) - [virtualInputTokens -= uint256(- inputTokenDelta)](src/Behodler3Tokenlaunch.sol#L437)
      [Behodler3Tokenlaunch.virtualInputTokens](src/Behodler3Tokenlaunch.sol#L145) can be used in cross function reentrancies: - [Behodler3Tokenlaunch.\_calculateBondingTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L527-L532) - [Behodler3Tokenlaunch.\_calculateInputTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L540-L545) - [Behodler3Tokenlaunch.\_calculateVirtualLiquidityQuote(uint256,uint256,uint256)](src/Behodler3Tokenlaunch.sol#L353-L384) - [Behodler3Tokenlaunch.\_getCurrentMarginalPriceInternal()](src/Behodler3Tokenlaunch.sol#L405-L412) - [Behodler3Tokenlaunch.getTotalRaised()](src/Behodler3Tokenlaunch.sol#L302-L305) - [Behodler3Tokenlaunch.getVirtualPair()](src/Behodler3Tokenlaunch.sol#L790-L792) - [Behodler3Tokenlaunch.setGoals(uint256,uint256,uint256)](src/Behodler3Tokenlaunch.sol#L239-L272) - [Behodler3Tokenlaunch.virtualInputTokens](src/Behodler3Tokenlaunch.sol#L145) - [\_updateVirtualLiquidityState(- int256(baseInputTokens),int256(bondingTokenAmount))](src/Behodler3Tokenlaunch.sol#L703) - [virtualL += uint256(bondingTokenDelta)](src/Behodler3Tokenlaunch.sol#L442) - [virtualL -= uint256(- bondingTokenDelta)](src/Behodler3Tokenlaunch.sol#L444)
      [Behodler3Tokenlaunch.virtualL](src/Behodler3Tokenlaunch.sol#L148) can be used in cross function reentrancies: - [Behodler3Tokenlaunch.\_calculateBondingTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L527-L532) - [Behodler3Tokenlaunch.\_calculateInputTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L540-L545) - [Behodler3Tokenlaunch.getVirtualPair()](src/Behodler3Tokenlaunch.sol#L790-L792) - [Behodler3Tokenlaunch.setGoals(uint256,uint256,uint256)](src/Behodler3Tokenlaunch.sol#L239-L272) - [Behodler3Tokenlaunch.virtualL](src/Behodler3Tokenlaunch.sol#L148) - [Behodler3Tokenlaunch.virtualLDifferentFromTotalSupply()](src/Behodler3Tokenlaunch.sol#L806-L808)

src/Behodler3Tokenlaunch.sol#L633-L708

- [ ] ID-17
      Reentrancy in [Behodler3Tokenlaunch.addLiquidityWithPermit(uint256,uint256,uint256,uint8,bytes32,bytes32)](src/Behodler3Tokenlaunch.sol#L863-L943):
      External calls: - [this.permit(msg.sender,address(this),inputAmount,deadline,v,r,s)](src/Behodler3Tokenlaunch.sol#L877-L884) - [(hookFee,deltaBondingToken) = \_bondingCurveHook.buy(msg.sender,baseBondingTokens,inputAmount)](src/Behodler3Tokenlaunch.sol#L894-L898) - [! inputToken.transferFrom(msg.sender,address(this),inputAmount)](src/Behodler3Tokenlaunch.sol#L927) - [vault.deposit(address(inputToken),inputAmount,address(this))](src/Behodler3Tokenlaunch.sol#L930) - [bondingToken.mint(msg.sender,bondingTokensOut)](src/Behodler3Tokenlaunch.sol#L934)
      State variables written after the call(s): - [\_updateVirtualLiquidityState(int256(effectiveInputAmount),- int256(baseBondingTokens))](src/Behodler3Tokenlaunch.sol#L938) - [virtualInputTokens += uint256(inputTokenDelta)](src/Behodler3Tokenlaunch.sol#L435) - [virtualInputTokens -= uint256(- inputTokenDelta)](src/Behodler3Tokenlaunch.sol#L437)
      [Behodler3Tokenlaunch.virtualInputTokens](src/Behodler3Tokenlaunch.sol#L145) can be used in cross function reentrancies: - [Behodler3Tokenlaunch.\_calculateBondingTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L527-L532) - [Behodler3Tokenlaunch.\_calculateInputTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L540-L545) - [Behodler3Tokenlaunch.\_calculateVirtualLiquidityQuote(uint256,uint256,uint256)](src/Behodler3Tokenlaunch.sol#L353-L384) - [Behodler3Tokenlaunch.\_getCurrentMarginalPriceInternal()](src/Behodler3Tokenlaunch.sol#L405-L412) - [Behodler3Tokenlaunch.getTotalRaised()](src/Behodler3Tokenlaunch.sol#L302-L305) - [Behodler3Tokenlaunch.getVirtualPair()](src/Behodler3Tokenlaunch.sol#L790-L792) - [Behodler3Tokenlaunch.setGoals(uint256,uint256,uint256)](src/Behodler3Tokenlaunch.sol#L239-L272) - [Behodler3Tokenlaunch.virtualInputTokens](src/Behodler3Tokenlaunch.sol#L145) - [\_updateVirtualLiquidityState(int256(effectiveInputAmount),- int256(baseBondingTokens))](src/Behodler3Tokenlaunch.sol#L938) - [virtualL += uint256(bondingTokenDelta)](src/Behodler3Tokenlaunch.sol#L442) - [virtualL -= uint256(- bondingTokenDelta)](src/Behodler3Tokenlaunch.sol#L444)
      [Behodler3Tokenlaunch.virtualL](src/Behodler3Tokenlaunch.sol#L148) can be used in cross function reentrancies: - [Behodler3Tokenlaunch.\_calculateBondingTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L527-L532) - [Behodler3Tokenlaunch.\_calculateInputTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L540-L545) - [Behodler3Tokenlaunch.getVirtualPair()](src/Behodler3Tokenlaunch.sol#L790-L792) - [Behodler3Tokenlaunch.setGoals(uint256,uint256,uint256)](src/Behodler3Tokenlaunch.sol#L239-L272) - [Behodler3Tokenlaunch.virtualL](src/Behodler3Tokenlaunch.sol#L148) - [Behodler3Tokenlaunch.virtualLDifferentFromTotalSupply()](src/Behodler3Tokenlaunch.sol#L806-L808)

src/Behodler3Tokenlaunch.sol#L863-L943

- [ ] ID-18
      Reentrancy in [Behodler3Tokenlaunch.addLiquidity(uint256,uint256)](src/Behodler3Tokenlaunch.sol#L556-L624):
      External calls: - [(hookFee,deltaBondingToken) = \_bondingCurveHook.buy(msg.sender,baseBondingTokens,inputAmount)](src/Behodler3Tokenlaunch.sol#L575-L579) - [! inputToken.transferFrom(msg.sender,address(this),inputAmount)](src/Behodler3Tokenlaunch.sol#L608) - [vault.deposit(address(inputToken),inputAmount,address(this))](src/Behodler3Tokenlaunch.sol#L611) - [bondingToken.mint(msg.sender,bondingTokensOut)](src/Behodler3Tokenlaunch.sol#L615)
      State variables written after the call(s): - [\_updateVirtualLiquidityState(int256(effectiveInputAmount),- int256(baseBondingTokens))](src/Behodler3Tokenlaunch.sol#L619) - [virtualInputTokens += uint256(inputTokenDelta)](src/Behodler3Tokenlaunch.sol#L435) - [virtualInputTokens -= uint256(- inputTokenDelta)](src/Behodler3Tokenlaunch.sol#L437)
      [Behodler3Tokenlaunch.virtualInputTokens](src/Behodler3Tokenlaunch.sol#L145) can be used in cross function reentrancies: - [Behodler3Tokenlaunch.\_calculateBondingTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L527-L532) - [Behodler3Tokenlaunch.\_calculateInputTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L540-L545) - [Behodler3Tokenlaunch.\_calculateVirtualLiquidityQuote(uint256,uint256,uint256)](src/Behodler3Tokenlaunch.sol#L353-L384) - [Behodler3Tokenlaunch.\_getCurrentMarginalPriceInternal()](src/Behodler3Tokenlaunch.sol#L405-L412) - [Behodler3Tokenlaunch.getTotalRaised()](src/Behodler3Tokenlaunch.sol#L302-L305) - [Behodler3Tokenlaunch.getVirtualPair()](src/Behodler3Tokenlaunch.sol#L790-L792) - [Behodler3Tokenlaunch.setGoals(uint256,uint256,uint256)](src/Behodler3Tokenlaunch.sol#L239-L272) - [Behodler3Tokenlaunch.virtualInputTokens](src/Behodler3Tokenlaunch.sol#L145) - [\_updateVirtualLiquidityState(int256(effectiveInputAmount),- int256(baseBondingTokens))](src/Behodler3Tokenlaunch.sol#L619) - [virtualL += uint256(bondingTokenDelta)](src/Behodler3Tokenlaunch.sol#L442) - [virtualL -= uint256(- bondingTokenDelta)](src/Behodler3Tokenlaunch.sol#L444)
      [Behodler3Tokenlaunch.virtualL](src/Behodler3Tokenlaunch.sol#L148) can be used in cross function reentrancies: - [Behodler3Tokenlaunch.\_calculateBondingTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L527-L532) - [Behodler3Tokenlaunch.\_calculateInputTokensOut(uint256)](src/Behodler3Tokenlaunch.sol#L540-L545) - [Behodler3Tokenlaunch.getVirtualPair()](src/Behodler3Tokenlaunch.sol#L790-L792) - [Behodler3Tokenlaunch.setGoals(uint256,uint256,uint256)](src/Behodler3Tokenlaunch.sol#L239-L272) - [Behodler3Tokenlaunch.virtualL](src/Behodler3Tokenlaunch.sol#L148) - [Behodler3Tokenlaunch.virtualLDifferentFromTotalSupply()](src/Behodler3Tokenlaunch.sol#L806-L808)

src/Behodler3Tokenlaunch.sol#L556-L624

- [ ] ID-19
      Reentrancy in [Behodler3Tokenlaunch.initializeVaultApproval()](src/Behodler3Tokenlaunch.sol#L474-L481):
      External calls: - [! inputToken.approve(address(vault),type()(uint256).max)](src/Behodler3Tokenlaunch.sol#L478)
      State variables written after the call(s): - [vaultApprovalInitialized = true](src/Behodler3Tokenlaunch.sol#L480)
      [Behodler3Tokenlaunch.vaultApprovalInitialized](src/Behodler3Tokenlaunch.sol#L141) can be used in cross function reentrancies: - [Behodler3Tokenlaunch.\_setInputToken(IERC20)](src/Behodler3Tokenlaunch.sol#L459-L467) - [Behodler3Tokenlaunch.\_setVault(IVault)](src/Behodler3Tokenlaunch.sol#L510-L519) - [Behodler3Tokenlaunch.constructor(IERC20,IBondingToken,IVault)](src/Behodler3Tokenlaunch.sol#L213-L228) - [Behodler3Tokenlaunch.disableToken()](src/Behodler3Tokenlaunch.sol#L487-L494) - [Behodler3Tokenlaunch.initializeVaultApproval()](src/Behodler3Tokenlaunch.sol#L474-L481) - [Behodler3Tokenlaunch.vaultApprovalInitialized](src/Behodler3Tokenlaunch.sol#L141)

src/Behodler3Tokenlaunch.sol#L474-L481

## shadowing-local

Impact: Low
Confidence: High

- [ ] ID-20
      [MockBondingToken.constructor(string,string).name](src/mocks/MockBondingToken.sol#L14) shadows: - [ERC20.name()](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L52-L54) (function) - [IERC20Metadata.name()](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L15) (function)

src/mocks/MockBondingToken.sol#L14

- [ ] ID-21
      [MockERC20.constructor(string,string,uint8).symbol](src/mocks/MockERC20.sol#L16) shadows: - [ERC20.symbol()](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L60-L62) (function) - [IERC20Metadata.symbol()](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L20) (function)

src/mocks/MockERC20.sol#L16

- [ ] ID-22
      [MockERC20.constructor(string,string,uint8).name](src/mocks/MockERC20.sol#L15) shadows: - [ERC20.name()](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L52-L54) (function) - [IERC20Metadata.name()](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L15) (function)

src/mocks/MockERC20.sol#L15

- [ ] ID-23
      [Behodler3Tokenlaunch.nonces(address).owner](src/Behodler3Tokenlaunch.sol#L951) shadows: - [Ownable.owner()](lib/vault/lib/openzeppelin-contracts/contracts/access/Ownable.sol#L56-L58) (function)

src/Behodler3Tokenlaunch.sol#L951

- [ ] ID-24
      [Behodler3Tokenlaunch.permit(address,address,uint256,uint256,uint8,bytes32,bytes32).owner](src/Behodler3Tokenlaunch.sol#L824) shadows: - [Ownable.owner()](lib/vault/lib/openzeppelin-contracts/contracts/access/Ownable.sol#L56-L58) (function)

src/Behodler3Tokenlaunch.sol#L824

- [ ] ID-25
      [MockBondingToken.constructor(string,string).symbol](src/mocks/MockBondingToken.sol#L14) shadows: - [ERC20.symbol()](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L60-L62) (function) - [IERC20Metadata.symbol()](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L20) (function)

src/mocks/MockBondingToken.sol#L14

## missing-zero-check

Impact: Low
Confidence: Medium

- [ ] ID-26
      [MockSellHook.sell(address,uint256,uint256).seller](src/mocks/MockSellHook.sol#L51) lacks a zero-check on : - [lastSeller = seller](src/mocks/MockSellHook.sol#L56)

src/mocks/MockSellHook.sol#L51

- [ ] ID-27
      [MockBuyHook.sell(address,uint256,uint256).seller](src/mocks/MockBuyHook.sol#L51) lacks a zero-check on : - [lastSeller = seller](src/mocks/MockBuyHook.sol#L56)

src/mocks/MockBuyHook.sol#L51

- [ ] ID-28
      [MockEarlySellPenaltyHook.sell(address,uint256,uint256).seller](src/mocks/MockEarlySellPenaltyHook.sol#L59) lacks a zero-check on : - [lastSeller = seller](src/mocks/MockEarlySellPenaltyHook.sol#L68)

src/mocks/MockEarlySellPenaltyHook.sol#L59

- [ ] ID-29
      [MockZeroHook.buy(address,uint256,uint256).buyer](src/mocks/MockZeroHook.sol#L21) lacks a zero-check on : - [lastBuyer = buyer](src/mocks/MockZeroHook.sol#L26)

src/mocks/MockZeroHook.sol#L21

- [ ] ID-30
      [MockEarlySellPenaltyHook.buy(address,uint256,uint256).buyer](src/mocks/MockEarlySellPenaltyHook.sol#L35) lacks a zero-check on : - [lastBuyer = buyer](src/mocks/MockEarlySellPenaltyHook.sol#L44)

src/mocks/MockEarlySellPenaltyHook.sol#L35

- [ ] ID-31
      [MockSellHook.buy(address,uint256,uint256).buyer](src/mocks/MockSellHook.sol#L38) lacks a zero-check on : - [lastBuyer = buyer](src/mocks/MockSellHook.sol#L43)

src/mocks/MockSellHook.sol#L38

- [ ] ID-32
      [MockBuyHook.buy(address,uint256,uint256).buyer](src/mocks/MockBuyHook.sol#L38) lacks a zero-check on : - [lastBuyer = buyer](src/mocks/MockBuyHook.sol#L43)

src/mocks/MockBuyHook.sol#L38

- [ ] ID-33
      [MockZeroHook.sell(address,uint256,uint256).seller](src/mocks/MockZeroHook.sol#L34) lacks a zero-check on : - [lastSeller = seller](src/mocks/MockZeroHook.sol#L39)

src/mocks/MockZeroHook.sol#L34

## reentrancy-events

Impact: Low
Confidence: Medium

- [ ] ID-34
      Reentrancy in [Behodler3Tokenlaunch.permit(address,address,uint256,uint256,uint8,bytes32,bytes32)](src/Behodler3Tokenlaunch.sol#L823-L850):
      External calls: - [IERC20Permit(address(inputToken)).permit(owner,spender,value,deadline,v,r,s)](src/Behodler3Tokenlaunch.sol#L842-L849)
      Event emitted after the call(s): - [PermitUsed(owner,spender,value,nonce,deadline)](src/Behodler3Tokenlaunch.sol#L844)

src/Behodler3Tokenlaunch.sol#L823-L850

## timestamp

Impact: Low
Confidence: Medium

- [ ] ID-35
      [MockEarlySellPenaltyHook.getHoursElapsed(address)](src/mocks/MockEarlySellPenaltyHook.sol#L129-L135) uses timestamp for comparisons
      Dangerous comparisons: - [lastBuyTimestamp == 0](src/mocks/MockEarlySellPenaltyHook.sol#L131)

src/mocks/MockEarlySellPenaltyHook.sol#L129-L135

- [ ] ID-36
      [EarlySellPenaltyHook.\_getHoursElapsed(address)](src/EarlySellPenaltyHook.sol#L204-L221) uses timestamp for comparisons
      Dangerous comparisons: - [lastBuyTimestamp == 0](src/EarlySellPenaltyHook.sol#L210)

src/EarlySellPenaltyHook.sol#L204-L221

- [ ] ID-37
      [EarlySellPenaltyHook.calculatePenaltyFee(address)](src/EarlySellPenaltyHook.sol#L132-L168) uses timestamp for comparisons
      Dangerous comparisons: - [lastBuyTimestamp == 0](src/EarlySellPenaltyHook.sol#L145) - [hoursElapsed >= maxPenaltyDurationHours](src/EarlySellPenaltyHook.sol#L154) - [penalty > 1000](src/EarlySellPenaltyHook.sol#L167)

src/EarlySellPenaltyHook.sol#L132-L168

- [ ] ID-38
      [EarlySellPenaltyHook.sell(address,uint256,uint256)](src/EarlySellPenaltyHook.sol#L75-L104) uses timestamp for comparisons
      Dangerous comparisons: - [penaltyFee > 0](src/EarlySellPenaltyHook.sol#L95)

src/EarlySellPenaltyHook.sol#L75-L104

- [ ] ID-39
      [Behodler3Tokenlaunch.permit(address,address,uint256,uint256,uint8,bytes32,bytes32)](src/Behodler3Tokenlaunch.sol#L823-L850) uses timestamp for comparisons
      Dangerous comparisons: - [deadline < block.timestamp](src/Behodler3Tokenlaunch.sol#L832)

src/Behodler3Tokenlaunch.sol#L823-L850

- [ ] ID-40
      [MockEarlySellPenaltyHook.calculatePenaltyFee(address)](src/mocks/MockEarlySellPenaltyHook.sol#L104-L126) uses timestamp for comparisons
      Dangerous comparisons: - [lastBuyTimestamp == 0](src/mocks/MockEarlySellPenaltyHook.sol#L108) - [hoursElapsed >= maxPenaltyDurationHours](src/mocks/MockEarlySellPenaltyHook.sol#L117) - [penalty > 1000](src/mocks/MockEarlySellPenaltyHook.sol#L125)

src/mocks/MockEarlySellPenaltyHook.sol#L104-L126

- [ ] ID-41
      [MockEarlySellPenaltyHook.sell(address,uint256,uint256)](src/mocks/MockEarlySellPenaltyHook.sol#L58-L83) uses timestamp for comparisons
      Dangerous comparisons: - [penaltyFee > 0](src/mocks/MockEarlySellPenaltyHook.sol#L76)

src/mocks/MockEarlySellPenaltyHook.sol#L58-L83

## assembly

Impact: Informational
Confidence: High

- [ ] ID-42
      [StorageSlot.getInt256Slot(bytes32)](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L102-L106) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L103-L105)

lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L102-L106

- [ ] ID-43
      [Math.tryMul(uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L73-L84) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L76-L80)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L73-L84

- [ ] ID-44
      [Panic.panic(uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/Panic.sol#L50-L56) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/Panic.sol#L51-L55)

lib/vault/lib/openzeppelin-contracts/contracts/utils/Panic.sol#L50-L56

- [ ] ID-45
      [SafeCast.toUint(bool)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol#L1157-L1161) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol#L1158-L1160)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol#L1157-L1161

- [ ] ID-46
      [Math.add512(uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L25-L30) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L26-L29)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L25-L30

- [ ] ID-47
      [Math.mulDiv(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L227-L234) - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L240-L249)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275

- [ ] ID-48
      [ECDSA.tryRecover(bytes32,bytes)](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol#L56-L75) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol#L66-L70)

lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol#L56-L75

- [ ] ID-49
      [StorageSlot.getUint256Slot(bytes32)](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L93-L97) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L94-L96)

lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L93-L97

- [ ] ID-50
      [Math.tryModExp(uint256,uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L409-L433) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L411-L432)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L409-L433

- [ ] ID-51
      [StorageSlot.getBytesSlot(bytes)](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L138-L142) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L139-L141)

lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L138-L142

- [ ] ID-52
      [Math.tryModExp(bytes,bytes,bytes)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L449-L471) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L461-L470)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L449-L471

- [ ] ID-53
      [StorageSlot.getAddressSlot(bytes32)](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L66-L70) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L67-L69)

lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L66-L70

- [ ] ID-54
      [StorageSlot.getBytesSlot(bytes32)](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L129-L133) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L130-L132)

lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L129-L133

- [ ] ID-55
      [StorageSlot.getStringSlot(string)](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L120-L124) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L121-L123)

lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L120-L124

- [ ] ID-56
      [MessageHashUtils.toTypedDataHash(bytes32,bytes32)](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L90-L98) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L91-L97)

lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L90-L98

- [ ] ID-57
      [Strings.escapeJSON(string)](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L446-L476) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L470-L473)

lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L446-L476

- [ ] ID-58
      [StorageSlot.getBytes32Slot(bytes32)](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L84-L88) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L85-L87)

lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L84-L88

- [ ] ID-59
      [StorageSlot.getStringSlot(bytes32)](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L111-L115) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L112-L114)

lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L111-L115

- [ ] ID-60
      [MessageHashUtils.toEthSignedMessageHash(bytes32)](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L30-L36) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L31-L35)

lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L30-L36

- [ ] ID-61
      [Strings.\_unsafeReadBytesOffset(bytes,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L484-L489) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L486-L488)

lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L484-L489

- [ ] ID-62
      [Strings.toString(uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L45-L63) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L50-L52) - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L55-L57)

lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L45-L63

- [ ] ID-63
      [Math.mul512(uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L37-L46) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L41-L45)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L37-L46

- [ ] ID-64
      [Strings.toChecksumHexString(address)](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L111-L129) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L116-L118)

lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L111-L129

- [ ] ID-65
      [MessageHashUtils.toDataWithIntendedValidatorHash(address,bytes32)](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L69-L79) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L73-L78)

lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L69-L79

- [ ] ID-66
      [StorageSlot.getBooleanSlot(bytes32)](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L75-L79) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L76-L78)

lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L75-L79

- [ ] ID-67
      [Math.tryDiv(uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L89-L97) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L92-L95)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L89-L97

- [ ] ID-68
      [Math.log2(uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L612-L651) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L648-L650)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L612-L651

- [ ] ID-69
      [Math.tryMod(uint256,uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L102-L110) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L105-L108)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L102-L110

- [ ] ID-70
      [ShortStrings.toString(ShortString)](lib/vault/lib/openzeppelin-contracts/contracts/utils/ShortStrings.sol#L63-L72) uses assembly - [INLINE ASM](lib/vault/lib/openzeppelin-contracts/contracts/utils/ShortStrings.sol#L67-L70)

lib/vault/lib/openzeppelin-contracts/contracts/utils/ShortStrings.sol#L63-L72

## pragma

Impact: Informational
Confidence: High

- [ ] ID-71
      5 different versions of Solidity are used: - Version constraint ^0.8.20 is used by: -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/Context.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/Panic.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/ShortStrings.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L5) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L4) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol#L5) -[^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol#L4) - Version constraint >=0.4.16 is used by: -[>=0.4.16](lib/vault/lib/openzeppelin-contracts/contracts/interfaces/IERC5267.sol#L4) -[>=0.4.16](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4) -[>=0.4.16](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol#L4) - Version constraint >=0.8.4 is used by: -[>=0.8.4](lib/vault/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol#L3) - Version constraint >=0.6.2 is used by: -[>=0.6.2](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L4) - Version constraint ^0.8.13 is used by: -[^0.8.13](lib/vault/src/interfaces/IVault.sol#L2) -[^0.8.13](src/Behodler3Tokenlaunch.sol#L2) -[^0.8.13](src/EarlySellPenaltyHook.sol#L2) -[^0.8.13](src/interfaces/IBondingCurveHook.sol#L2) -[^0.8.13](src/interfaces/IBondingToken.sol#L2) -[^0.8.13](src/interfaces/IEarlySellPenaltyHook.sol#L2) -[^0.8.13](src/mocks/MockBondingToken.sol#L2) -[^0.8.13](src/mocks/MockBuyHook.sol#L2) -[^0.8.13](src/mocks/MockERC20.sol#L2) -[^0.8.13](src/mocks/MockEarlySellPenaltyHook.sol#L2) -[^0.8.13](src/mocks/MockFailingHook.sol#L2) -[^0.8.13](src/mocks/MockSellHook.sol#L2) -[^0.8.13](src/mocks/MockZeroHook.sol#L2)

lib/vault/lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4

## cyclomatic-complexity

Impact: Informational
Confidence: High

- [ ] ID-72
      [Behodler3Tokenlaunch.removeLiquidity(uint256,uint256)](src/Behodler3Tokenlaunch.sol#L633-L708) has a high cyclomatic complexity (12).

src/Behodler3Tokenlaunch.sol#L633-L708

- [ ] ID-73
      [Behodler3Tokenlaunch.addLiquidityWithPermit(uint256,uint256,uint256,uint8,bytes32,bytes32)](src/Behodler3Tokenlaunch.sol#L863-L943) has a high cyclomatic complexity (13).

src/Behodler3Tokenlaunch.sol#L863-L943

## solc-version

Impact: Informational
Confidence: High

- [ ] ID-74
      Version constraint >=0.4.16 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html) - DirtyBytesArrayToStorage - ABIDecodeTwoDimensionalArrayMemory - KeccakCaching - EmptyByteArrayCopy - DynamicArrayCleanup - ImplicitConstructorCallvalueCheck - TupleAssignmentMultiStackSlotComponents - MemoryArrayCreationOverflow - privateCanBeOverridden - SignedArrayStorageCopy - ABIEncoderV2StorageArrayWithMultiSlotElement - DynamicConstructorArgumentsClippedABIV2 - UninitializedFunctionPointerInConstructor_0.4.x - IncorrectEventSignatureInLibraries_0.4.x - ExpExponentCleanup - NestedArrayFunctionCallDecoder - ZeroFunctionSelector.
      It is used by: - [>=0.4.16](lib/vault/lib/openzeppelin-contracts/contracts/interfaces/IERC5267.sol#L4) - [>=0.4.16](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4) - [>=0.4.16](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol#L4)

lib/vault/lib/openzeppelin-contracts/contracts/interfaces/IERC5267.sol#L4

- [ ] ID-75
      Version constraint ^0.8.13 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html) - VerbatimInvalidDeduplication - FullInlinerNonExpressionSplitArgumentEvaluationOrder - MissingSideEffectsOnSelectorAccess - StorageWriteRemovalBeforeConditionalTermination - AbiReencodingHeadOverflowWithStaticArrayCleanup - DirtyBytesArrayToStorage - InlineAssemblyMemorySideEffects - DataLocationChangeInInternalOverride - NestedCalldataArrayAbiReencodingSizeValidation.
      It is used by: - [^0.8.13](lib/vault/src/interfaces/IVault.sol#L2) - [^0.8.13](src/Behodler3Tokenlaunch.sol#L2) - [^0.8.13](src/EarlySellPenaltyHook.sol#L2) - [^0.8.13](src/interfaces/IBondingCurveHook.sol#L2) - [^0.8.13](src/interfaces/IBondingToken.sol#L2) - [^0.8.13](src/interfaces/IEarlySellPenaltyHook.sol#L2) - [^0.8.13](src/mocks/MockBondingToken.sol#L2) - [^0.8.13](src/mocks/MockBuyHook.sol#L2) - [^0.8.13](src/mocks/MockERC20.sol#L2) - [^0.8.13](src/mocks/MockEarlySellPenaltyHook.sol#L2) - [^0.8.13](src/mocks/MockFailingHook.sol#L2) - [^0.8.13](src/mocks/MockSellHook.sol#L2) - [^0.8.13](src/mocks/MockZeroHook.sol#L2)

lib/vault/src/interfaces/IVault.sol#L2

- [ ] ID-76
      Version constraint >=0.8.4 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html) - FullInlinerNonExpressionSplitArgumentEvaluationOrder - MissingSideEffectsOnSelectorAccess - AbiReencodingHeadOverflowWithStaticArrayCleanup - DirtyBytesArrayToStorage - DataLocationChangeInInternalOverride - NestedCalldataArrayAbiReencodingSizeValidation - SignedImmutables.
      It is used by: - [>=0.8.4](lib/vault/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol#L3)

lib/vault/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol#L3

- [ ] ID-77
      Version constraint >=0.6.2 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html) - MissingSideEffectsOnSelectorAccess - AbiReencodingHeadOverflowWithStaticArrayCleanup - DirtyBytesArrayToStorage - NestedCalldataArrayAbiReencodingSizeValidation - ABIDecodeTwoDimensionalArrayMemory - KeccakCaching - EmptyByteArrayCopy - DynamicArrayCleanup - MissingEscapingInFormatting - ArraySliceDynamicallyEncodedBaseType - ImplicitConstructorCallvalueCheck - TupleAssignmentMultiStackSlotComponents - MemoryArrayCreationOverflow.
      It is used by: - [>=0.6.2](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L4)

lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L4

- [ ] ID-78
      Version constraint ^0.8.20 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html) - VerbatimInvalidDeduplication - FullInlinerNonExpressionSplitArgumentEvaluationOrder - MissingSideEffectsOnSelectorAccess.
      It is used by: - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/Context.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/Panic.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/ShortStrings.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol#L5) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/Strings.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L4) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol#L5) - [^0.8.20](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol#L4)

lib/vault/lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4

## missing-inheritance

Impact: Informational
Confidence: High

- [ ] ID-79
      [Behodler3Tokenlaunch](src/Behodler3Tokenlaunch.sol#L39-L973) should inherit from [IERC20Permit](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol#L42-L90)

src/Behodler3Tokenlaunch.sol#L39-L973

- [ ] ID-80
      [MockERC20](src/mocks/MockERC20.sol#L11-L34) should inherit from [IBondingToken](src/interfaces/IBondingToken.sol#L10-L25)

src/mocks/MockERC20.sol#L11-L34

## naming-convention

Impact: Informational
Confidence: High

- [ ] ID-81
      Parameter [Behodler3Tokenlaunch.setHook(IBondingCurveHook).\_hook](src/Behodler3Tokenlaunch.sol#L770) is not in mixedCase

src/Behodler3Tokenlaunch.sol#L770

- [ ] ID-82
      Parameter [EarlySellPenaltyHook.setPenaltyParameters(uint256,uint256).\_maxDurationHours](src/EarlySellPenaltyHook.sol#L177) is not in mixedCase

src/EarlySellPenaltyHook.sol#L177

- [ ] ID-83
      Parameter [MockBuyHook.setBuyParams(uint256,int256).\_fee](src/mocks/MockBuyHook.sol#L64) is not in mixedCase

src/mocks/MockBuyHook.sol#L64

- [ ] ID-84
      Parameter [EarlySellPenaltyHook.setPenaltyParameters(uint256,uint256).\_declineRatePerHour](src/EarlySellPenaltyHook.sol#L177) is not in mixedCase

src/EarlySellPenaltyHook.sol#L177

- [ ] ID-85
      Parameter [MockSellHook.setBuyParams(uint256,int256).\_deltaBondingToken](src/mocks/MockSellHook.sol#L64) is not in mixedCase

src/mocks/MockSellHook.sol#L64

- [ ] ID-86
      Parameter [MockSellHook.setSellParams(uint256,int256).\_fee](src/mocks/MockSellHook.sol#L69) is not in mixedCase

src/mocks/MockSellHook.sol#L69

- [ ] ID-87
      Parameter [Behodler3Tokenlaunch.setGoals(uint256,uint256,uint256).\_seedInput](src/Behodler3Tokenlaunch.sol#L239) is not in mixedCase

src/Behodler3Tokenlaunch.sol#L239

- [ ] ID-88
      Parameter [Behodler3Tokenlaunch.setGoals(uint256,uint256,uint256).\_fundingGoal](src/Behodler3Tokenlaunch.sol#L239) is not in mixedCase

src/Behodler3Tokenlaunch.sol#L239

- [ ] ID-89
      Parameter [MockEarlySellPenaltyHook.setPenaltyParameters(uint256,uint256).\_maxDurationHours](src/mocks/MockEarlySellPenaltyHook.sol#L89) is not in mixedCase

src/mocks/MockEarlySellPenaltyHook.sol#L89

- [ ] ID-90
      Parameter [Behodler3Tokenlaunch.setGoals(uint256,uint256,uint256).\_desiredAveragePrice](src/Behodler3Tokenlaunch.sol#L239) is not in mixedCase

src/Behodler3Tokenlaunch.sol#L239

- [ ] ID-91
      Parameter [MockEarlySellPenaltyHook.setPenaltyActive(bool).\_active](src/mocks/MockEarlySellPenaltyHook.sol#L95) is not in mixedCase

src/mocks/MockEarlySellPenaltyHook.sol#L95

- [ ] ID-92
      Function [EIP712.\_EIP712Version()](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol#L157-L159) is not in mixedCase

lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol#L157-L159

- [ ] ID-93
      Function [Behodler3Tokenlaunch.DOMAIN_SEPARATOR()](src/Behodler3Tokenlaunch.sol#L960-L962) is not in mixedCase

src/Behodler3Tokenlaunch.sol#L960-L962

- [ ] ID-94
      Parameter [MockFailingHook.setRevertMessages(string,string).\_buyMessage](src/mocks/MockFailingHook.sol#L67) is not in mixedCase

src/mocks/MockFailingHook.sol#L67

- [ ] ID-95
      Parameter [MockBuyHook.setBuyParams(uint256,int256).\_deltaBondingToken](src/mocks/MockBuyHook.sol#L64) is not in mixedCase

src/mocks/MockBuyHook.sol#L64

- [ ] ID-96
      Parameter [MockEarlySellPenaltyHook.setPenaltyParameters(uint256,uint256).\_declineRatePerHour](src/mocks/MockEarlySellPenaltyHook.sol#L89) is not in mixedCase

src/mocks/MockEarlySellPenaltyHook.sol#L89

- [ ] ID-97
      Parameter [MockBuyHook.setSellParams(uint256,int256).\_deltaBondingToken](src/mocks/MockBuyHook.sol#L69) is not in mixedCase

src/mocks/MockBuyHook.sol#L69

- [ ] ID-98
      Parameter [MockFailingHook.setRevertMessages(string,string).\_sellMessage](src/mocks/MockFailingHook.sol#L67) is not in mixedCase

src/mocks/MockFailingHook.sol#L67

- [ ] ID-99
      Parameter [Behodler3Tokenlaunch.setInputToken(address).\_token](src/Behodler3Tokenlaunch.sol#L455) is not in mixedCase

src/Behodler3Tokenlaunch.sol#L455

- [ ] ID-100
      Function [IERC20Permit.DOMAIN_SEPARATOR()](lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol#L89) is not in mixedCase

lib/vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol#L89

- [ ] ID-101
      Parameter [MockEarlySellPenaltyHook.setFailureMode(bool,bool).\_shouldFailOnBuy](src/mocks/MockEarlySellPenaltyHook.sol#L150) is not in mixedCase

src/mocks/MockEarlySellPenaltyHook.sol#L150

- [ ] ID-102
      Parameter [MockSellHook.setBuyParams(uint256,int256).\_fee](src/mocks/MockSellHook.sol#L64) is not in mixedCase

src/mocks/MockSellHook.sol#L64

- [ ] ID-103
      Parameter [MockEarlySellPenaltyHook.setFailureMode(bool,bool).\_shouldFailOnSell](src/mocks/MockEarlySellPenaltyHook.sol#L150) is not in mixedCase

src/mocks/MockEarlySellPenaltyHook.sol#L150

- [ ] ID-104
      Parameter [EarlySellPenaltyHook.setPenaltyActive(bool).\_active](src/EarlySellPenaltyHook.sol#L192) is not in mixedCase

src/EarlySellPenaltyHook.sol#L192

- [ ] ID-105
      Parameter [Behodler3Tokenlaunch.setAutoLock(bool).\_autoLock](src/Behodler3Tokenlaunch.sol#L762) is not in mixedCase

src/Behodler3Tokenlaunch.sol#L762

- [ ] ID-106
      Parameter [MockFailingHook.setFailureMode(bool,bool).\_buyFail](src/mocks/MockFailingHook.sol#L62) is not in mixedCase

src/mocks/MockFailingHook.sol#L62

- [ ] ID-107
      Function [EIP712.\_EIP712Name()](lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol#L146-L148) is not in mixedCase

lib/vault/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol#L146-L148

- [ ] ID-108
      Parameter [MockSellHook.setSellParams(uint256,int256).\_deltaBondingToken](src/mocks/MockSellHook.sol#L69) is not in mixedCase

src/mocks/MockSellHook.sol#L69

- [ ] ID-109
      Parameter [MockBuyHook.setSellParams(uint256,int256).\_fee](src/mocks/MockBuyHook.sol#L69) is not in mixedCase

src/mocks/MockBuyHook.sol#L69

- [ ] ID-110
      Parameter [MockFailingHook.setFailureMode(bool,bool).\_sellFail](src/mocks/MockFailingHook.sol#L62) is not in mixedCase

src/mocks/MockFailingHook.sol#L62

- [ ] ID-111
      Parameter [Behodler3Tokenlaunch.setVault(address).\_vault](src/Behodler3Tokenlaunch.sol#L501) is not in mixedCase

src/Behodler3Tokenlaunch.sol#L501

## too-many-digits

Impact: Informational
Confidence: Medium

- [ ] ID-112
      [ShortStrings.slitherConstructorConstantVariables()](lib/vault/lib/openzeppelin-contracts/contracts/utils/ShortStrings.sol#L40-L122) uses literals with too many digits: - [FALLBACK_SENTINEL = 0x00000000000000000000000000000000000000000000000000000000000000FF](lib/vault/lib/openzeppelin-contracts/contracts/utils/ShortStrings.sol#L42)

lib/vault/lib/openzeppelin-contracts/contracts/utils/ShortStrings.sol#L40-L122

- [ ] ID-113
      [Math.log2(uint256)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L612-L651) uses literals with too many digits: - [r = r | byte(uint256,uint256)(x >> r,0x0000010102020202030303030303030300000000000000000000000000000000)](lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L649)

lib/vault/lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L612-L651

## unused-state

Impact: Informational
Confidence: High

- [ ] ID-114
      [Behodler3Tokenlaunch.\_PERMIT_TYPEHASH](src/Behodler3Tokenlaunch.sol#L43-L44) is never used in [Behodler3Tokenlaunch](src/Behodler3Tokenlaunch.sol#L39-L973)

src/Behodler3Tokenlaunch.sol#L43-L44

## immutable-states

Impact: Optimization
Confidence: High

- [ ] ID-115
      [Behodler3Tokenlaunch.bondingToken](src/Behodler3Tokenlaunch.sol#L132) should be immutable

src/Behodler3Tokenlaunch.sol#L132

- [ ] ID-116
      [MockERC20.\_decimals](src/mocks/MockERC20.sol#L12) should be immutable

src/mocks/MockERC20.sol#L12
