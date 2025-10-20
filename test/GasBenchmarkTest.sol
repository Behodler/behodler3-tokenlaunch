// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockBondingToken.sol";
import "@vault/mocks/MockVault.sol";

/**
 * @title Gas Benchmark Test for TokenLaunch Contract
 * @notice Comprehensive gas analysis for all key operations before and after optimizations
 * @dev Tests measure gas consumption to identify optimization opportunities and validate improvements
 */
contract GasBenchmarkTest is Test {
    Behodler3Tokenlaunch public tokenLaunch;
    MockERC20 public inputToken;
    MockBondingToken public bondingToken;
    MockVault public vault;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    uint256 constant INPUT_DECIMALS = 18;
    uint256 constant INITIAL_SUPPLY = 1000000 * 10**INPUT_DECIMALS;

    // Test parameters
    uint256 constant FUNDING_GOAL = 100000 * 10**INPUT_DECIMALS; // 100k tokens
    uint256 constant DESIRED_AVG_PRICE = 900000000000000000; // ~0.9 (90% of 1e18)

    // Test amounts for different scenarios
    uint256 constant SMALL_AMOUNT = 100 * 10**INPUT_DECIMALS; // 100 tokens
    uint256 constant MEDIUM_AMOUNT = 1000 * 10**INPUT_DECIMALS; // 1k tokens
    uint256 constant LARGE_AMOUNT = 10000 * 10**INPUT_DECIMALS; // 10k tokens

    struct GasMeasurement {
        string operation;
        uint256 gasUsed;
        uint256 timestamp;
        string context;
    }

    GasMeasurement[] public measurements;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);

        // Deploy mock contracts
        inputToken = new MockERC20("Test Token", "TEST", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));

        // Deploy TokenLaunch contract
        tokenLaunch = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)),
            IBondingToken(address(bondingToken)),
            IYieldStrategy(address(vault))
        );

        // Setup vault authorization
        vault.setClient(address(tokenLaunch), true);

        // Initialize vault approval
        tokenLaunch.initializeVaultApproval();

        // Mint tokens to test users
        inputToken.mint(user1, INITIAL_SUPPLY);
        inputToken.mint(user2, INITIAL_SUPPLY);
        inputToken.mint(user3, INITIAL_SUPPLY);
        inputToken.mint(owner, INITIAL_SUPPLY);

        // Set up virtual liquidity parameters
        tokenLaunch.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    function recordGas(string memory operation, uint256 gasStart, string memory context) internal {
        uint256 gasUsed = gasStart - gasleft();
        measurements.push(GasMeasurement({
            operation: operation,
            gasUsed: gasUsed,
            timestamp: block.timestamp,
            context: context
        }));

        console.log("Gas used for %s (%s): %d", operation, context, gasUsed);
    }

    function testBaselineGasOperations() public {
        console.log("=== BASELINE GAS MEASUREMENTS ===");

        // Test addLiquidity operations
        _testAddLiquidityGas();

        // Test removeLiquidity operations
        _testRemoveLiquidityGas();

        // Test quote operations
        _testQuoteOperationsGas();

        // Test view function gas costs
        _testViewFunctionsGas();

        // Test owner operations
        _testOwnerOperationsGas();

        // Generate summary
        _generateGasSummary();
    }

    function _testAddLiquidityGas() internal {
        console.log("--- Testing addLiquidity Gas Usage ---");

        // Test small amount
        vm.startPrank(user1);
        inputToken.approve(address(tokenLaunch), SMALL_AMOUNT);
        uint256 gasStart = gasleft();
        tokenLaunch.addLiquidity(SMALL_AMOUNT, 0);
        recordGas("addLiquidity", gasStart, "small_amount_100_tokens");
        vm.stopPrank();

        // Test medium amount
        vm.startPrank(user2);
        inputToken.approve(address(tokenLaunch), MEDIUM_AMOUNT);
        gasStart = gasleft();
        tokenLaunch.addLiquidity(MEDIUM_AMOUNT, 0);
        recordGas("addLiquidity", gasStart, "medium_amount_1k_tokens");
        vm.stopPrank();

        // Test large amount
        vm.startPrank(user3);
        inputToken.approve(address(tokenLaunch), LARGE_AMOUNT);
        gasStart = gasleft();
        tokenLaunch.addLiquidity(LARGE_AMOUNT, 0);
        recordGas("addLiquidity", gasStart, "large_amount_10k_tokens");
        vm.stopPrank();

        // Test subsequent addLiquidity by same user (no new storage)
        vm.startPrank(user1);
        inputToken.approve(address(tokenLaunch), SMALL_AMOUNT);
        gasStart = gasleft();
        tokenLaunch.addLiquidity(SMALL_AMOUNT, 0);
        recordGas("addLiquidity", gasStart, "subsequent_same_user");
        vm.stopPrank();
    }

    function _testRemoveLiquidityGas() internal {
        console.log("--- Testing removeLiquidity Gas Usage ---");

        // Setup: Add liquidity first
        vm.startPrank(user1);
        inputToken.approve(address(tokenLaunch), MEDIUM_AMOUNT * 2);
        tokenLaunch.addLiquidity(MEDIUM_AMOUNT * 2, 0);
        uint256 bondingBalance = bondingToken.balanceOf(user1);
        vm.stopPrank();

        // Test small removal (no fees)
        uint256 smallRemoval = bondingBalance / 10;
        vm.startPrank(user1);
        uint256 gasStart = gasleft();
        tokenLaunch.removeLiquidity(smallRemoval, 0);
        recordGas("removeLiquidity", gasStart, "small_removal_no_fee");
        vm.stopPrank();

        // Test with withdrawal fee
        tokenLaunch.setWithdrawalFee(500); // 5% fee

        vm.startPrank(user1);
        uint256 mediumRemoval = bondingBalance / 5;
        gasStart = gasleft();
        tokenLaunch.removeLiquidity(mediumRemoval, 0);
        recordGas("removeLiquidity", gasStart, "medium_removal_5pct_fee");
        vm.stopPrank();

        // Test large removal with fee
        vm.startPrank(user1);
        uint256 remainingBalance = bondingToken.balanceOf(user1);
        gasStart = gasleft();
        tokenLaunch.removeLiquidity(remainingBalance, 0);
        recordGas("removeLiquidity", gasStart, "large_removal_5pct_fee");
        vm.stopPrank();

        // Reset fee to 0
        tokenLaunch.setWithdrawalFee(0);
    }

    function _testQuoteOperationsGas() internal {
        console.log("--- Testing Quote Operations Gas Usage ---");

        // Test quoteAddLiquidity
        uint256 gasStart = gasleft();
        tokenLaunch.quoteAddLiquidity(MEDIUM_AMOUNT);
        recordGas("quoteAddLiquidity", gasStart, "medium_amount");

        gasStart = gasleft();
        tokenLaunch.quoteAddLiquidity(LARGE_AMOUNT);
        recordGas("quoteAddLiquidity", gasStart, "large_amount");

        // Test quoteRemoveLiquidity (need bonding tokens first)
        vm.startPrank(user1);
        inputToken.approve(address(tokenLaunch), MEDIUM_AMOUNT);
        tokenLaunch.addLiquidity(MEDIUM_AMOUNT, 0);
        uint256 bondingBalance = bondingToken.balanceOf(user1);
        vm.stopPrank();

        gasStart = gasleft();
        tokenLaunch.quoteRemoveLiquidity(bondingBalance / 2);
        recordGas("quoteRemoveLiquidity", gasStart, "half_balance_no_fee");

        // Test quote with fee
        tokenLaunch.setWithdrawalFee(250); // 2.5% fee
        gasStart = gasleft();
        tokenLaunch.quoteRemoveLiquidity(bondingBalance);
        recordGas("quoteRemoveLiquidity", gasStart, "full_balance_2.5pct_fee");

        // Reset fee
        tokenLaunch.setWithdrawalFee(0);
    }

    function _testViewFunctionsGas() internal {
        console.log("--- Testing View Functions Gas Usage ---");

        uint256 gasStart;

        // Price functions
        gasStart = gasleft();
        tokenLaunch.getCurrentMarginalPrice();
        recordGas("getCurrentMarginalPrice", gasStart, "view_function");

        gasStart = gasleft();
        tokenLaunch.getInitialMarginalPrice();
        recordGas("getInitialMarginalPrice", gasStart, "view_function");

        gasStart = gasleft();
        tokenLaunch.getFinalMarginalPrice();
        recordGas("getFinalMarginalPrice", gasStart, "view_function");

        gasStart = gasleft();
        tokenLaunch.getAveragePrice();
        recordGas("getAveragePrice", gasStart, "view_function");

        // State functions
        gasStart = gasleft();
        tokenLaunch.getTotalRaised();
        recordGas("getTotalRaised", gasStart, "view_function");

        gasStart = gasleft();
        tokenLaunch.getVirtualPair();
        recordGas("getVirtualPair", gasStart, "view_function");

        gasStart = gasleft();
        tokenLaunch.isVirtualPairInitialized();
        recordGas("isVirtualPairInitialized", gasStart, "view_function");

        gasStart = gasleft();
        tokenLaunch.virtualLDifferentFromTotalSupply();
        recordGas("virtualLDifferentFromTotalSupply", gasStart, "view_function");
    }

    function _testOwnerOperationsGas() internal {
        console.log("--- Testing Owner Operations Gas Usage ---");

        uint256 gasStart;

        // Lock/unlock operations
        gasStart = gasleft();
        tokenLaunch.lock();
        recordGas("lock", gasStart, "owner_operation");

        gasStart = gasleft();
        tokenLaunch.unlock();
        recordGas("unlock", gasStart, "owner_operation");

        // Fee setting
        gasStart = gasleft();
        tokenLaunch.setWithdrawalFee(100); // 1%
        recordGas("setWithdrawalFee", gasStart, "owner_operation");

        // Auto-lock setting
        gasStart = gasleft();
        tokenLaunch.setAutoLock(true);
        recordGas("setAutoLock", gasStart, "owner_operation");

        gasStart = gasleft();
        tokenLaunch.setAutoLock(false);
        recordGas("setAutoLock", gasStart, "owner_operation");

        // Goal setting (expensive operation)
        gasStart = gasleft();
        tokenLaunch.setGoals(FUNDING_GOAL * 2, DESIRED_AVG_PRICE);
        recordGas("setGoals", gasStart, "owner_operation");

        // Reset to original goals
        tokenLaunch.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);
        tokenLaunch.setWithdrawalFee(0);
    }

    function _generateGasSummary() internal view {
        console.log("\n=== GAS USAGE SUMMARY ===");
        console.log("Total measurements taken: %d", measurements.length);

        // Calculate averages by operation type
        string[10] memory operations = [
            "addLiquidity",
            "removeLiquidity",
            "quoteAddLiquidity",
            "quoteRemoveLiquidity",
            "getCurrentMarginalPrice",
            "getAveragePrice",
            "getTotalRaised",
            "lock",
            "setWithdrawalFee",
            "setGoals"
        ];

        for (uint i = 0; i < operations.length; i++) {
            string memory op = operations[i];
            uint256 total = 0;
            uint256 count = 0;
            uint256 min = type(uint256).max;
            uint256 max = 0;

            for (uint j = 0; j < measurements.length; j++) {
                if (keccak256(bytes(measurements[j].operation)) == keccak256(bytes(op))) {
                    total += measurements[j].gasUsed;
                    count++;
                    if (measurements[j].gasUsed < min) min = measurements[j].gasUsed;
                    if (measurements[j].gasUsed > max) max = measurements[j].gasUsed;
                }
            }

            if (count > 0) {
                console.log("Operation:", op);
                console.log("  avg gas:", total/count);
                console.log("  min gas:", min);
                console.log("  max gas:", max);
                console.log("  samples:", count);
            }
        }

        console.log("=== END SUMMARY ===\n");
    }

    function testGasOptimizedVirtualLiquidityCalculations() public {
        console.log("=== TESTING OPTIMIZED VIRTUAL LIQUIDITY CALCULATIONS ===");

        // Test the optimized path (zero seed case)
        assertTrue(tokenLaunch.seedInput() == 0, "Should be using zero seed");

        // Get current virtual pair state
        (uint256 virtualInputTokens, uint256 virtualL, uint256 virtualK) = tokenLaunch.getVirtualPair();

        console.log("Virtual state - Input: %d, L: %d, K: %d", virtualInputTokens, virtualL, virtualK);

        // Test that optimized calculation matches expected behavior
        uint256 testAmount = 1000 * 10**INPUT_DECIMALS;

        vm.startPrank(user1);
        inputToken.approve(address(tokenLaunch), testAmount);

        // Get quote first
        uint256 quotedBondingTokens = tokenLaunch.quoteAddLiquidity(testAmount);
        console.log("Quoted bonding tokens for %d input: %d", testAmount, quotedBondingTokens);

        // Measure gas for optimized calculation
        uint256 gasStart = gasleft();
        uint256 actualBondingTokens = tokenLaunch.addLiquidity(testAmount, 0);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Actual bonding tokens: %d, Gas used: %d", actualBondingTokens, gasUsed);

        // Verify quote accuracy
        assertEq(quotedBondingTokens, actualBondingTokens, "Quote should match actual result");

        vm.stopPrank();
    }

    function testGasWithDifferentFeeScenarios() public {
        console.log("=== TESTING GAS WITH DIFFERENT FEE SCENARIOS ===");

        // Setup some liquidity first
        vm.startPrank(user1);
        inputToken.approve(address(tokenLaunch), LARGE_AMOUNT);
        tokenLaunch.addLiquidity(LARGE_AMOUNT, 0);
        uint256 bondingBalance = bondingToken.balanceOf(user1);
        vm.stopPrank();

        uint256[] memory feeRates = new uint256[](5);
        feeRates[0] = 0;     // 0%
        feeRates[1] = 100;   // 1%
        feeRates[2] = 500;   // 5%
        feeRates[3] = 1000;  // 10%
        feeRates[4] = 2500;  // 25%

        for (uint i = 0; i < feeRates.length; i++) {
            // Set fee rate
            tokenLaunch.setWithdrawalFee(feeRates[i]);

            // Test quote gas
            uint256 gasStart = gasleft();
            tokenLaunch.quoteRemoveLiquidity(bondingBalance / 10);
            uint256 quoteGas = gasStart - gasleft();

            // Test actual removal gas (small amount to preserve balance)
            vm.startPrank(user1);
            gasStart = gasleft();
            tokenLaunch.removeLiquidity(bondingBalance / 20, 0);
            uint256 removeGas = gasStart - gasleft();
            vm.stopPrank();

            console.log("Fee %d%% - Quote gas: %d, Remove gas: %d",
                feeRates[i] / 100, quoteGas, removeGas);
        }

        // Reset fee to 0
        tokenLaunch.setWithdrawalFee(0);
    }

    function testGasUnderExtremeConditions() public {
        console.log("=== TESTING GAS UNDER EXTREME CONDITIONS ===");

        // Test very small amounts (dust)
        uint256 dustAmount = 1; // 1 wei
        vm.startPrank(user1);
        inputToken.approve(address(tokenLaunch), dustAmount);

        uint256 gasStart = gasleft();
        tokenLaunch.addLiquidity(dustAmount, 0);
        recordGas("addLiquidity", gasStart, "dust_amount_1_wei");
        vm.stopPrank();

        // Test with maximum possible amount (within limits)
        uint256 maxSafeAmount = FUNDING_GOAL / 2; // Half of funding goal
        vm.startPrank(user2);
        inputToken.approve(address(tokenLaunch), maxSafeAmount);

        gasStart = gasleft();
        tokenLaunch.addLiquidity(maxSafeAmount, 0);
        recordGas("addLiquidity", gasStart, "max_safe_amount");
        vm.stopPrank();

        // Test quote operations at extreme values
        gasStart = gasleft();
        tokenLaunch.quoteAddLiquidity(1);
        recordGas("quoteAddLiquidity", gasStart, "dust_quote");

        gasStart = gasleft();
        tokenLaunch.quoteAddLiquidity(maxSafeAmount);
        recordGas("quoteAddLiquidity", gasStart, "max_safe_quote");
    }
}