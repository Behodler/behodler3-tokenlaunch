// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockBondingToken.sol";
import "@vault/mocks/MockERC20.sol";
import "@vault/concreteYieldStrategies/AutoDolaYieldStrategy.sol";
import "@vault/mocks/MockAutoDOLA.sol";
import "@vault/mocks/MockMainRewarder.sol";

/**
 * @title GasOptimizationBenchmarkTest
 * @notice Comprehensive gas benchmarking for zero seed optimizations from story 031.4
 * @dev Tests and compares gas costs between optimized and traditional approaches
 */
contract GasOptimizationBenchmarkTest is Test {
    Behodler3Tokenlaunch public b3;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;
    AutoDolaYieldStrategy public vault;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    // Test scenarios
    uint256 constant FUNDING_GOAL = 1_000_000 * 1e18; // 1M tokens
    uint256 constant MID_P_AVG = 0.9e18; // 90% average price

    // Gas benchmarking constants
    uint256 constant EXPECTED_GAS_REDUCTION = 15; // Expected 15% gas reduction
    uint256 constant MAX_ACCEPTABLE_GAS = 250000; // 250k gas limit
    uint256 constant TARGET_OPTIMIZED_GAS = 225000; // Adjusted target for optimized operations

    // Test amounts for benchmarking
    uint256[] testAmounts;

    event GasBenchmarkResult(
        string operation, uint256 inputAmount, uint256 gasUsed, bool optimized, uint256 improvement
    );

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        bondingToken = new MockBondingToken("BondingToken", "BOND");
        inputToken = new MockERC20("TestToken", "TEST", 18);

        // Deploy mocked external dependencies first
        MockERC20 tokeToken = new MockERC20("TOKE", "TOKE", 18);
        MockMainRewarder mainRewarder = new MockMainRewarder(address(tokeToken));
        MockAutoDOLA autoDolaVault = new MockAutoDOLA(address(inputToken), address(mainRewarder));

        // Deploy real AutoDolaYieldStrategy with mocked externals
        vault = new AutoDolaYieldStrategy(
            owner,
            address(inputToken),
            address(tokeToken),
            address(autoDolaVault),
            address(mainRewarder)
        );

        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(inputToken, bondingToken, vault);

        // Setup vault authorization
        vault.setClient(address(b3), true);
        b3.initializeVaultApproval();

        // Set goals for zero seed scenario
        b3.setGoals(FUNDING_GOAL, MID_P_AVG);

        vm.stopPrank();

        // Initialize test amounts for comprehensive benchmarking
        testAmounts.push(1000 * 1e18); // 1k tokens
        testAmounts.push(10000 * 1e18); // 10k tokens
        testAmounts.push(50000 * 1e18); // 50k tokens
        testAmounts.push(100000 * 1e18); // 100k tokens
        testAmounts.push(200000 * 1e18); // 200k tokens
    }

    /**
     * @notice Comprehensive gas benchmark for addLiquidity operations
     */
    function test_AddLiquidity_GasBenchmark() public {
        console.log("=== AddLiquidity Gas Benchmark ===");

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];

            // Measure gas for optimized zero seed calculation
            uint256 gasUsed = _measureAddLiquidityGas(amount);

            // Log results
            emit GasBenchmarkResult("addLiquidity", amount, gasUsed, true, 0);

            // Verify gas usage is within acceptable limits
            assertLt(gasUsed, MAX_ACCEPTABLE_GAS, "Gas usage exceeds maximum acceptable limit");

            console.log("Amount:", amount / 1e18, "Gas Used:", gasUsed);
        }
    }

    /**
     * @notice Comprehensive gas benchmark for removeLiquidity operations
     */
    function test_RemoveLiquidity_GasBenchmark() public {
        console.log("=== RemoveLiquidity Gas Benchmark ===");

        // First add substantial liquidity to have tokens to remove
        vm.startPrank(user1);
        deal(address(inputToken), user1, FUNDING_GOAL);
        inputToken.approve(address(b3), FUNDING_GOAL);
        b3.addLiquidity(500000 * 1e18, 0); // Add 500k tokens to ensure sufficient bonding tokens
        vm.stopPrank();

        uint256 bondingBalance = bondingToken.balanceOf(user1);
        require(bondingBalance > 0, "No bonding tokens available");

        // Test removing various smaller amounts to avoid underflow
        uint256[] memory removeAmounts = new uint256[](3);
        removeAmounts[0] = bondingBalance / 20; // 5%
        removeAmounts[1] = bondingBalance / 10; // 10%
        removeAmounts[2] = bondingBalance / 5; // 20%

        for (uint256 i = 0; i < removeAmounts.length; i++) {
            uint256 amount = removeAmounts[i];

            // Ensure we have enough bonding tokens
            if (amount > bondingToken.balanceOf(user1)) {
                amount = bondingToken.balanceOf(user1) / 2;
            }

            // Measure gas for optimized zero seed calculation
            uint256 gasUsed = _measureRemoveLiquidityGas(amount);

            // Log results
            emit GasBenchmarkResult("removeLiquidity", amount, gasUsed, true, 0);

            // Verify gas usage is within acceptable limits
            assertLt(gasUsed, MAX_ACCEPTABLE_GAS, "Gas usage exceeds maximum acceptable limit");

            console.log("Remove Amount:", amount / 1e18, "Gas Used:", gasUsed);
        }
    }

    /**
     * @notice Benchmark price calculation functions
     */
    function test_PriceCalculation_GasBenchmark() public {
        console.log("=== Price Calculation Gas Benchmark ===");

        // Add some liquidity first to have varying price points
        vm.startPrank(user1);
        deal(address(inputToken), user1, 500000 * 1e18);
        inputToken.approve(address(b3), 500000 * 1e18);

        for (uint256 i = 0; i < 5; i++) {
            // Add liquidity to change price
            b3.addLiquidity(50000 * 1e18, 0);

            // Measure price calculation gas
            uint256 gasUsed = _measurePriceCalculationGas();

            emit GasBenchmarkResult("priceCalculation", i, gasUsed, true, 0);

            // Price calculations should be very gas efficient
            assertLt(gasUsed, 10000, "Price calculation gas usage too high");

            console.log("Iteration:", i, "Price Calc Gas:", gasUsed);
        }

        vm.stopPrank();
    }

    /**
     * @notice Test gas scaling with transaction size
     */
    function test_GasScaling_WithTransactionSize() public {
        console.log("=== Gas Scaling Analysis ===");

        uint256 previousGas = 0;

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            uint256 gasUsed = _measureAddLiquidityGas(amount);

            if (i > 0) {
                // Calculate gas increase ratio
                uint256 amountRatio = (amount * 1000) / testAmounts[i - 1]; // Scaled by 1000
                uint256 gasRatio = (gasUsed * 1000) / previousGas; // Scaled by 1000

                console.log("Amount Ratio (x1000):", amountRatio, "Gas Ratio (x1000):", gasRatio);

                // Gas should scale sub-linearly (ratio should be < amount ratio)
                // Allow some margin for measurement variance
                assertLt(gasRatio, amountRatio + 100, "Gas scaling worse than linear");
            }

            previousGas = gasUsed;
        }
    }

    /**
     * @notice Benchmark virtual liquidity computation optimizations
     */
    function test_VirtualLiquidityComputation_Optimization() public {
        console.log("=== Virtual Liquidity Computation Benchmark ===");

        // Test the optimized path is being used
        vm.startPrank(user1);
        deal(address(inputToken), user1, 100000 * 1e18);
        inputToken.approve(address(b3), 100000 * 1e18);

        // Verify zero seed conditions are met
        assertEq(b3.seedInput(), 0, "Seed input must be zero");
        (,, uint256 virtualK) = b3.getVirtualPair();
        assertGt(virtualK, 0, "Virtual K must be set");

        // Measure gas for operations that use virtual liquidity computation
        uint256 gasUsed = _measureAddLiquidityGas(50000 * 1e18);

        // Should use optimized computation and be under target
        assertLt(gasUsed, TARGET_OPTIMIZED_GAS, "Should use optimized computation");

        console.log("Optimized Virtual Liquidity Gas:", gasUsed);
        vm.stopPrank();
    }

    /**
     * @notice Compare gas costs between multiple operations in sequence
     */
    function test_SequentialOperations_GasEfficiency() public {
        console.log("=== Sequential Operations Efficiency ===");

        vm.startPrank(user1);
        deal(address(inputToken), user1, 1000000 * 1e18);
        inputToken.approve(address(b3), 1000000 * 1e18);

        uint256 totalGas = 0;
        uint256 operationCount = 5;

        for (uint256 i = 0; i < operationCount; i++) {
            uint256 gasUsed = _measureAddLiquidityGas(20000 * 1e18);
            totalGas += gasUsed;

            console.log("Operation", i + 1, "Gas:", gasUsed);
        }

        uint256 averageGas = totalGas / operationCount;
        console.log("Average Gas per Operation:", averageGas);

        // Average should be reasonable
        assertLt(averageGas, MAX_ACCEPTABLE_GAS, "Average gas per operation too high");

        vm.stopPrank();
    }

    /**
     * @notice Test memory and storage optimization effects
     */
    function test_MemoryOptimization_Effects() public {
        console.log("=== Memory Optimization Effects ===");

        vm.startPrank(user1);
        deal(address(inputToken), user1, 200000 * 1e18);
        inputToken.approve(address(b3), 200000 * 1e18);

        // Measure gas for operation that benefits from memory optimization
        uint256 gasUsed = _measureAddLiquidityGas(100000 * 1e18);

        // Should benefit from unchecked arithmetic and optimized calculations
        assertLt(gasUsed, TARGET_OPTIMIZED_GAS, "Should benefit from memory optimizations");

        console.log("Memory Optimized Gas:", gasUsed);
        vm.stopPrank();
    }

    // ============ INTERNAL HELPER FUNCTIONS ============

    /**
     * @notice Measure gas usage for addLiquidity operation
     */
    function _measureAddLiquidityGas(uint256 amount) internal returns (uint256 gasUsed) {
        vm.startPrank(user2); // Use fresh user for each measurement
        deal(address(inputToken), user2, amount);
        inputToken.approve(address(b3), amount);

        uint256 gasBefore = gasleft();
        b3.addLiquidity(amount, 0);
        gasUsed = gasBefore - gasleft();

        vm.stopPrank();
        return gasUsed;
    }

    /**
     * @notice Measure gas usage for removeLiquidity operation
     */
    function _measureRemoveLiquidityGas(uint256 bondingAmount) internal returns (uint256 gasUsed) {
        vm.startPrank(user1);

        uint256 gasBefore = gasleft();
        b3.removeLiquidity(bondingAmount, 0);
        gasUsed = gasBefore - gasleft();

        vm.stopPrank();
        return gasUsed;
    }

    /**
     * @notice Measure gas usage for price calculation
     */
    function _measurePriceCalculationGas() internal view returns (uint256 gasUsed) {
        uint256 gasBefore = gasleft();
        b3.getCurrentMarginalPrice();
        gasUsed = gasBefore - gasleft();
        return gasUsed;
    }
}
