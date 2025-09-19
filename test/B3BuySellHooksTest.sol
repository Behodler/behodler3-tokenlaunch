// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/interfaces/IBondingCurveHook.sol";
import "../src/mocks/MockBuyHook.sol";
import "../src/mocks/MockSellHook.sol";
import "../src/mocks/MockFailingHook.sol";
import "../src/mocks/MockZeroHook.sol";
import "../src/mocks/MockERC20.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";

/**
 * @title B3BuySellHooksTest
 * @notice Comprehensive failing tests for buy and sell hooks in Behodler3Tokenlaunch
 * @dev TDD Red Phase - All tests should fail because hook functionality is not implemented
 */
contract B3BuySellHooksTest is Test {
    Behodler3Tokenlaunch public b3;
    MockERC20 public inputToken;
    MockBondingToken public bondingToken;
    MockVault public vault;

    MockBuyHook public buyHook;
    MockSellHook public sellHook;
    MockFailingHook public failingHook;
    MockZeroHook public zeroHook;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint constant INITIAL_INPUT_SUPPLY = 1_000_000 * 1e18;
    uint constant TYPICAL_INPUT_AMOUNT = 1000 * 1e18;

    function setUp() public {
        // Deploy mock contracts
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));

        // Deploy B3 contract
        vm.startPrank(owner);
        b3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IVault(address(vault))
        );
        vm.stopPrank();

        // Set the bonding curve address in the vault to allow B3 to call deposit/withdraw
        vault.setClient(address(b3), true);

        // Initialize vault approval after vault authorizes B3
        vm.startPrank(owner);
        b3.initializeVaultApproval();

        // Set virtual liquidity goals
        uint fundingGoal = 1_000_000 * 1e18; // 1M tokens
        uint seedInput = 1000 * 1e18; // 1K tokens
        uint desiredAveragePrice = 0.9e18; // 0.9 (90% of final price)
        b3.setGoals(fundingGoal, seedInput, desiredAveragePrice);

        vm.stopPrank();

        // Deploy mock hooks
        buyHook = new MockBuyHook(5, 1000, 10, -500); // 0.5% buy fee, +1000 bonus, 1% sell fee, -500 discount
        sellHook = new MockSellHook(3, -200, 8, 300); // 0.3% buy fee, -200 penalty, 0.8% sell fee, +300 penalty
        failingHook = new MockFailingHook(true, true, "Buy hook failed", "Sell hook failed");
        zeroHook = new MockZeroHook();

        // Setup user balances
        inputToken.mint(user1, INITIAL_INPUT_SUPPLY);
        inputToken.mint(user2, INITIAL_INPUT_SUPPLY);

        // Approve spending
        vm.prank(user1);
        inputToken.approve(address(b3), type(uint).max);
        vm.prank(user2);
        inputToken.approve(address(b3), type(uint).max);
    }

    // ============ HOOK STORAGE AND MANAGEMENT TESTS (SHOULD FAIL) ============

    function test_SetHook_OnlyOwner_ShouldFail() public {
        // This should fail because setHook function doesn't exist
        vm.expectRevert();
        vm.prank(owner);
        (bool success,) = address(b3).call(abi.encodeWithSignature("setHook(address)", address(buyHook)));
        assertFalse(success, "setHook function should not exist yet");
    }

    function test_HookAddressStorage_ShouldFail() public {
        // This should fail because hook storage variable doesn't exist
        vm.expectRevert();
        (bool success, bytes memory data) = address(b3).call(abi.encodeWithSignature("hook()"));
        assertTrue(success, "hook storage variable should not exist yet");
    }

    function test_UnauthorizedSetHook_ShouldFail() public {
        // This should revert because user1 is not the owner
        vm.expectRevert();
        vm.prank(user1);
        b3.setHook(IBondingCurveHook(address(buyHook)));
    }

    function test_HookAddressRetrieval_ShouldFail() public {
        // This should fail because hook getter doesn't exist
        vm.expectRevert();
        (bool success, bytes memory data) = address(b3).call(abi.encodeWithSignature("getHook()"));
        assertFalse(success, "getHook function should not exist yet");
    }

    // ============ BUY HOOK INTEGRATION TESTS (SHOULD FAIL) ============

    function test_BuyHookCalledDuringAddLiquidity_ShouldFail() public {
        // Setup hook but this should fail because hook integration doesn't exist
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        uint initialBuyCallCount = buyHook.buyCallCount();

        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // This assertion should fail because hook isn't called
        assertEq(buyHook.buyCallCount(), initialBuyCallCount + 1, "Buy hook should have been called");
    }

    function test_BuyHookCallsAfterBaseCalculation_ShouldFail() public {
        // This should fail because hook integration doesn't exist
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        uint expectedBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT);

        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because hook call doesn't happen
        assertEq(buyHook.lastBaseBondingToken(), expectedBondingTokens, "Hook should receive base bonding token amount");
    }

    function test_BuyHookReceivesCorrectBuyerAddress_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because hook isn't called
        assertEq(buyHook.lastBuyer(), user1, "Hook should receive correct buyer address");
    }

    function test_BuyHookReceivesCorrectBaseBondingAmount_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        uint expectedAmount = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT);

        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because hook isn't called
        assertEq(
            buyHook.lastBaseBondingToken(), expectedAmount, "Hook should receive correct base bonding token amount"
        );
    }

    function test_BuyHookReceivesCorrectBaseInputAmount_ShouldFail() public {
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because hook isn't called
        assertEq(
            buyHook.lastBaseInputToken(), TYPICAL_INPUT_AMOUNT, "Hook should receive correct base input token amount"
        );
    }

    // ============ SELL HOOK INTEGRATION TESTS (SHOULD FAIL) ============

    function test_SellHookCalledDuringRemoveLiquidity_ShouldFail() public {
        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        // First add liquidity
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        uint initialSellCallCount = sellHook.sellCallCount();

        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);

        // Should fail because hook integration doesn't exist
        assertEq(sellHook.sellCallCount(), initialSellCallCount + 1, "Sell hook should have been called");
    }

    function test_SellHookCallsAfterBaseCalculation_ShouldFail() public {
        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        // Add liquidity first
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        uint expectedInputTokens = b3.quoteRemoveLiquidity(bondingTokens);

        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);

        // Should fail because hook call doesn't happen
        assertEq(sellHook.lastBaseInputToken(), expectedInputTokens, "Hook should receive base input token amount");
    }

    function test_SellHookReceivesCorrectSellerAddress_ShouldFail() public {
        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        // Add liquidity first
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);

        // Should fail because hook isn't called
        assertEq(sellHook.lastSeller(), user1, "Hook should receive correct seller address");
    }

    function test_SellHookReceivesCorrectBaseBondingAmount_ShouldFail() public {
        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        // Add liquidity first
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);

        // Should fail because hook isn't called
        assertEq(
            sellHook.lastBaseBondingToken(), bondingTokens, "Hook should receive correct base bonding token amount"
        );
    }

    function test_SellHookReceivesCorrectBaseInputAmount_ShouldFail() public {
        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        // Add liquidity first
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        uint expectedInputTokens = b3.quoteRemoveLiquidity(bondingTokens);

        vm.prank(user1);
        b3.removeLiquidity(bondingTokens, 0);

        // Should fail because hook isn't called
        assertEq(
            sellHook.lastBaseInputToken(), expectedInputTokens, "Hook should receive correct base input token amount"
        );
    }

    // ============ FEE CALCULATION TESTS (SHOULD FAIL) ============

    function test_BuyHookFeeAppliedToInputToken_ShouldFail() public {
        // Configure hook with 0.5% fee (5 out of 1000)
        buyHook.setBuyParams(5, 0);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        uint baseBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT);
        uint expectedFee = (TYPICAL_INPUT_AMOUNT * 5) / 1000; // 0.5%
        uint expectedBondingTokensAfterFee = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT - expectedFee);

        vm.prank(user1);
        uint actualBondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because fee logic doesn't exist
        assertEq(actualBondingTokens, expectedBondingTokensAfterFee, "Fee should be applied to input tokens");
    }

    function test_SellHookFeeAppliedToBondingToken_ShouldFail() public {
        // Configure hook with 1% fee (10 out of 1000)
        sellHook.setSellParams(10, 0);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        // Add liquidity first
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        uint expectedFee = (bondingTokens * 10) / 1000; // 1%
        uint expectedInputTokensAfterFee = b3.quoteRemoveLiquidity(bondingTokens - expectedFee);

        vm.prank(user1);
        uint actualInputTokens = b3.removeLiquidity(bondingTokens, 0);

        // Should fail because fee logic doesn't exist
        assertEq(actualInputTokens, expectedInputTokensAfterFee, "Fee should be applied to bonding token input");
    }

    function test_FeeCalculationWithZeroFee_ShouldFail() public {
        // Configure hook with 0% fee
        zeroHook.resetCallCounts();

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(zeroHook)));

        uint baseBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT);

        vm.prank(user1);
        uint actualBondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because fee logic doesn't exist (even with zero fee)
        assertEq(actualBondingTokens, baseBondingTokens, "Zero fee should result in base calculation");
        assertTrue(zeroHook.buyCallCount() > 0, "Hook should still be called with zero fee");
    }

    function test_FeeCalculationWithMaximumFee_ShouldFail() public {
        // Configure hook with 100% fee (1000 out of 1000)
        buyHook.setBuyParams(1000, 0);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        vm.prank(user1);
        vm.expectRevert("VL: Invalid calculation result");
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 1);

        // Should fail because fee logic doesn't exist
        // Note: This test expects the transaction to revert due to 100% fee making output 0
    }

    function test_FeeCalculationWithTypicalFee_ShouldFail() public {
        // Configure hook with 0.5% fee (5 out of 1000)
        buyHook.setBuyParams(5, 0);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        uint expectedFee = (TYPICAL_INPUT_AMOUNT * 5) / 1000;
        uint expectedBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT - expectedFee);

        vm.prank(user1);
        uint actualBondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because fee logic doesn't exist
        assertEq(actualBondingTokens, expectedBondingTokens, "Typical fee should be applied correctly");
    }

    // ============ DELTA BONDING TOKEN ADJUSTMENT TESTS (SHOULD FAIL) ============

    function test_PositiveDeltaBondingTokenIncreasesMintedTokensOnBuy_ShouldFail() public {
        // Configure hook with +1000 bonus
        buyHook.setBuyParams(0, 1000);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        uint baseBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT);
        uint expectedBondingTokens = baseBondingTokens + 1000;

        vm.prank(user1);
        uint actualBondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because adjustment logic doesn't exist
        assertEq(actualBondingTokens, expectedBondingTokens, "Positive delta should increase minted tokens");
    }

    function test_NegativeDeltaBondingTokenDecreasesMintedTokensOnBuy_ShouldFail() public {
        // Configure hook with -500 penalty
        buyHook.setBuyParams(0, -500);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        uint baseBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT);
        uint expectedBondingTokens = baseBondingTokens - 500;

        vm.prank(user1);
        uint actualBondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because adjustment logic doesn't exist
        assertEq(actualBondingTokens, expectedBondingTokens, "Negative delta should decrease minted tokens");
    }

    function test_PositiveDeltaBondingTokenIncreasesRequiredTokensOnSell_ShouldFail() public {
        // Configure hook with +300 bonus (increases output)
        sellHook.setSellParams(0, 300);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        // Add liquidity first
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        uint baseInputTokens = b3.quoteRemoveLiquidity(bondingTokens);
        uint adjustedBondingTokens = bondingTokens + 300;
        uint expectedInputTokens = b3.quoteRemoveLiquidity(adjustedBondingTokens);

        // Positive delta increases effective bonding amount, giving more output
        vm.prank(user1);
        uint actualInputTokens = b3.removeLiquidity(bondingTokens, 0);

        // Should get more output with positive delta
        assertGt(actualInputTokens, baseInputTokens, "Positive delta should increase output");
    }

    function test_NegativeDeltaBondingTokenDecreasesRequiredTokensOnSell_ShouldFail() public {
        // Add liquidity first without hook
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Configure hook with larger negative delta to see the effect (10% of bonding tokens)
        int negativeDelta = -int(bondingTokens / 10);
        sellHook.setSellParams(0, negativeDelta);

        // Set the hook after adding liquidity
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        uint baseInputTokens = b3.quoteRemoveLiquidity(bondingTokens);
        uint adjustedBondingTokens = uint(int(bondingTokens) + negativeDelta);
        uint expectedInputTokens = b3.quoteRemoveLiquidity(adjustedBondingTokens);

        vm.prank(user1);
        uint actualInputTokens = b3.removeLiquidity(bondingTokens, 0);

        // Negative delta reduces output (acts like a fee)
        assertLt(actualInputTokens, baseInputTokens, "Negative delta should reduce output");
        assertEq(actualInputTokens, expectedInputTokens, "Output should match expected calculation");
    }

    // ============ REVERT CONDITION TESTS (SHOULD FAIL) ============

    function test_BuyRevertsWhenNegativeDeltaExceedsBaseMinting_ShouldFail() public {
        uint baseBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT);

        // Configure hook with negative delta larger than base minting
        buyHook.setBuyParams(0, -int(baseBondingTokens + 1));

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        vm.prank(user1);
        vm.expectRevert("B3: Negative bonding token result");
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because validation doesn't exist
    }

    function test_SellRevertsWhenAdjustmentsResultInZeroOrNegative_ShouldFail() public {
        // Configure hook with large negative delta to make effective amount negative
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Set hook with negative delta larger than bonding tokens
        sellHook.setSellParams(0, -int(bondingTokens + 1));

        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        vm.prank(user1);
        vm.expectRevert("B3: Invalid bonding token amount after adjustment");
        b3.removeLiquidity(bondingTokens, 0);
    }

    function test_EdgeCaseDeltaEqualsNegativeBaseAmount_ShouldFail() public {
        uint baseBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT);

        // Configure hook with delta exactly equal to negative base amount
        buyHook.setBuyParams(0, -int(baseBondingTokens));

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        vm.prank(user1);
        vm.expectRevert("B3: Negative bonding token result");
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because validation doesn't exist
    }

    // ============ UNSET HOOK HANDLING TESTS (SHOULD FAIL) ============

    function test_BuyOperationSkipsHookWhenAddressIsZero_ShouldFail() public {
        // Don't set any hook (should be zero address by default)
        uint baseBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT);

        vm.prank(user1);
        uint actualBondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because zero-address check doesn't exist
        // When no hook is set, should behave normally
        assertEq(actualBondingTokens, baseBondingTokens, "Should work normally with no hook set");
    }

    function test_SellOperationSkipsHookWhenAddressIsZero_ShouldFail() public {
        // Add liquidity first
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        uint baseInputTokens = b3.quoteRemoveLiquidity(bondingTokens);

        vm.prank(user1);
        uint actualInputTokens = b3.removeLiquidity(bondingTokens, 0);

        // Should fail because zero-address check doesn't exist
        assertEq(actualInputTokens, baseInputTokens, "Should work normally with no hook set");
    }

    function test_NoRevertWithUnsetHooksDuringNormalOperations_ShouldFail() public {
        // This test ensures the contract doesn't revert when hooks are unset
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        vm.prank(user1);
        uint inputTokens = b3.removeLiquidity(bondingTokens, 0);

        // Should fail because hook handling doesn't exist
        assertGt(bondingTokens, 0, "Add liquidity should work without hooks");
        assertGt(inputTokens, 0, "Remove liquidity should work without hooks");
    }

    // ============ INTEGRATION TEST SCENARIOS (SHOULD FAIL) ============

    function test_CompleteBuyFlow_ShouldFail() public {
        // Configure hook with fee and delta
        buyHook.setBuyParams(5, 1000); // 0.5% fee, +1000 bonus

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        uint expectedFee = (TYPICAL_INPUT_AMOUNT * 5) / 1000;
        uint baseBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT - expectedFee);
        uint expectedBondingTokens = baseBondingTokens + 1000;

        vm.prank(user1);
        uint actualBondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because hook integration doesn't exist
        assertEq(actualBondingTokens, expectedBondingTokens, "Complete buy flow should work");
        assertEq(buyHook.buyCallCount(), 1, "Buy hook should have been called once");
    }

    function test_CompleteSellFlow_ShouldFail() public {
        // Configure hook with fee and delta
        sellHook.setSellParams(8, -200); // 0.8% fee, -200 discount

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        // Add liquidity first
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        uint expectedFee = (bondingTokens * 8) / 1000;
        uint adjustedBondingTokens = bondingTokens - expectedFee - 200;
        uint expectedInputTokens = b3.quoteRemoveLiquidity(adjustedBondingTokens);

        vm.prank(user1);
        uint actualInputTokens = b3.removeLiquidity(bondingTokens, 0);

        // Should fail because hook integration doesn't exist
        assertEq(actualInputTokens, expectedInputTokens, "Complete sell flow should work");
        assertEq(sellHook.sellCallCount(), 1, "Sell hook should have been called once");
    }

    function test_BuyWithPositiveDeltaBondingTokenBonus_ShouldFail() public {
        // Configure hook with large positive delta (bonus)
        buyHook.setBuyParams(0, 5000);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        uint baseBondingTokens = b3.quoteAddLiquidity(TYPICAL_INPUT_AMOUNT);
        uint expectedBondingTokens = baseBondingTokens + 5000;

        vm.prank(user1);
        uint actualBondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        // Should fail because adjustment logic doesn't exist
        assertEq(actualBondingTokens, expectedBondingTokens, "Positive delta bonus should work");
    }

    function test_SellWithNegativeDeltaBondingTokenDiscount_ShouldFail() public {
        // Configure hook with positive delta (discount/bonus)
        sellHook.setSellParams(0, 1000);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(sellHook)));

        // Add liquidity first
        vm.prank(user1);
        uint bondingTokens = b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);

        uint baseInputTokens = b3.quoteRemoveLiquidity(bondingTokens);
        uint adjustedInputTokens = b3.quoteRemoveLiquidity(bondingTokens + 1000);

        vm.prank(user1);
        uint actualInputTokens = b3.removeLiquidity(bondingTokens, 0);

        // Positive delta acts as bonus, increasing output
        assertGt(actualInputTokens, baseInputTokens, "Positive delta should act as discount/bonus");
    }

    // ============ EVENT EMISSION TESTS (SHOULD FAIL) ============

    function test_HookCallEventsEmitted_ShouldFail() public {
        // Configure hook
        buyHook.setBuyParams(5, 1000);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        // Should fail because events don't exist
        vm.expectEmit(true, true, true, true);
        emit HookCalled(address(buyHook), user1, "buy", 5, 1000);

        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
    }

    function test_FeeApplicationEventsEmitted_ShouldFail() public {
        // Configure hook with fee
        buyHook.setBuyParams(10, 0);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        uint expectedFee = (TYPICAL_INPUT_AMOUNT * 10) / 1000;

        // Should fail because events don't exist
        vm.expectEmit(true, true, true, true);
        emit FeeApplied(user1, expectedFee, "buy");

        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
    }

    function test_DeltaBondingTokenAdjustmentEventsEmitted_ShouldFail() public {
        // Configure hook with delta adjustment
        buyHook.setBuyParams(0, 2000);

        // Set the hook
        vm.prank(owner);
        b3.setHook(IBondingCurveHook(address(buyHook)));

        // Should fail because events don't exist
        vm.expectEmit(true, true, true, true);
        emit BondingTokenAdjusted(user1, 2000, "buy");

        vm.prank(user1);
        b3.addLiquidity(TYPICAL_INPUT_AMOUNT, 0);
    }

    // ============ EVENT DEFINITIONS (FOR COMPILATION) ============

    // These events don't exist in the contract yet, but are needed for compilation
    event HookCalled(address indexed hook, address indexed user, string operation, uint fee, int delta);
    event FeeApplied(address indexed user, uint fee, string operation);
    event BondingTokenAdjusted(address indexed user, int adjustment, string operation);
}
