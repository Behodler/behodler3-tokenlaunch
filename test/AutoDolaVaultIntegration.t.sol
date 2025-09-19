// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";
import "@vault/interfaces/IVault.sol";

/**
 * @title AutoDolaVaultIntegration
 * @notice Integration tests for AutoDola vault functionality with comprehensive gas benchmarking
 * @dev Tests cover current vault operations and prepare for future AutoDola-specific operations
 *
 * Test Coverage:
 * - Vault deposit operations with gas benchmarking
 * - Vault withdrawal operations with gas benchmarking
 * - Vault/tokenlaunch integration scenarios
 * - Edge cases and error conditions
 * - Future harvest/compound operation placeholders
 * - Gas optimization analysis across different operation sizes
 */
contract AutoDolaVaultIntegration is Test {
    // ============ CONTRACTS ============

    Behodler3Tokenlaunch public b3;
    MockVault public vault;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;

    // ============ TEST ACCOUNTS ============

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public vaultManager = address(0x4);

    // ============ GAS BENCHMARKING VARIABLES ============

    struct GasBenchmark {
        uint gasUsed;
        uint amount;
        string operation;
        string testCase;
    }

    GasBenchmark[] public gasBenchmarks;

    // Standard test amounts for consistent benchmarking
    uint public constant SMALL_AMOUNT = 1e15; // 0.001 tokens (18 decimals)
    uint public constant MEDIUM_AMOUNT = 1e18; // 1 token
    uint public constant LARGE_AMOUNT = 1000e18; // 1000 tokens
    uint public constant MAX_AMOUNT = type(uint).max / 1e6; // Safe max amount

    // ============ SETUP ============

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        inputToken = new MockERC20("AutoDola Input", "DOLA", 18);
        bondingToken = new MockBondingToken("AutoDola Bonding Token", "aDBOND");
        vault = new MockVault(owner);

        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IVault(address(vault))
        );

        // Authorize B3 contract to interact with vault
        vault.setClient(address(b3), true);

        // Authorize this test contract to interact with vault directly for testing
        vault.setClient(address(this), true);

        // Initialize vault approval in B3
        b3.initializeVaultApproval();

        // Set virtual liquidity goals
        uint fundingGoal = 1_000_000 * 1e18; // 1M tokens
        uint seedInput = 1000 * 1e18; // 1K tokens
        uint desiredAveragePrice = 0.9e18; // 0.9 (90% of final price)
        b3.setGoals(fundingGoal, seedInput, desiredAveragePrice);

        // Setup initial liquidity for meaningful tests
        inputToken.mint(address(this), 1_000_000e18);
        inputToken.mint(user1, 100_000e18);
        inputToken.mint(user2, 100_000e18);

        vm.stopPrank();

        // Setup user approvals
        vm.prank(user1);
        inputToken.approve(address(b3), type(uint).max);

        vm.prank(user2);
        inputToken.approve(address(b3), type(uint).max);

        // Clear gas benchmarks array
        delete gasBenchmarks;
    }

    // ============ GAS BENCHMARKING FRAMEWORK ============

    /**
     * @notice Records gas usage for a specific operation
     * @param operation The operation being benchmarked
     * @param testCase The specific test case
     * @param amount The amount involved in the operation
     * @param gasUsed The gas consumed
     */
    function recordGasBenchmark(string memory operation, string memory testCase, uint amount, uint gasUsed) internal {
        gasBenchmarks.push(GasBenchmark({gasUsed: gasUsed, amount: amount, operation: operation, testCase: testCase}));
    }

    /**
     * @notice Prints all gas benchmarks for analysis
     */
    function printGasBenchmarks() public view {
        console.log("=== GAS BENCHMARK RESULTS ===");
        console.log("Operation | Test Case | Amount | Gas Used");
        console.log("----------------------------------------");

        for (uint i = 0; i < gasBenchmarks.length; i++) {
            GasBenchmark memory benchmark = gasBenchmarks[i];
            console.log(
                string(
                    abi.encodePacked(
                        benchmark.operation,
                        " | ",
                        benchmark.testCase,
                        " | ",
                        vm.toString(benchmark.amount),
                        " | ",
                        vm.toString(benchmark.gasUsed)
                    )
                )
            );
        }

        console.log("==========================================");
    }

    // ============ DEPOSIT OPERATION TESTS WITH GAS BENCHMARKING ============

    /**
     * @notice Test vault deposit with small amount and measure gas
     */
    function test_VaultDeposit_SmallAmount_GasBenchmark() public {
        // Approve vault to spend tokens
        inputToken.approve(address(vault), SMALL_AMOUNT);

        // Measure gas for deposit
        uint gasBefore = gasleft();
        vault.deposit(address(inputToken), SMALL_AMOUNT, address(this));
        uint gasUsed = gasBefore - gasleft();

        // Record benchmark
        recordGasBenchmark("DEPOSIT", "small_amount", SMALL_AMOUNT, gasUsed);

        // Verify deposit
        assertEq(vault.balanceOf(address(inputToken), address(this)), SMALL_AMOUNT);
        assertEq(vault.getTotalDeposits(address(inputToken)), SMALL_AMOUNT);
    }

    /**
     * @notice Test vault deposit with medium amount and measure gas
     */
    function test_VaultDeposit_MediumAmount_GasBenchmark() public {
        inputToken.approve(address(vault), MEDIUM_AMOUNT);

        uint gasBefore = gasleft();
        vault.deposit(address(inputToken), MEDIUM_AMOUNT, address(this));
        uint gasUsed = gasBefore - gasleft();

        recordGasBenchmark("DEPOSIT", "medium_amount", MEDIUM_AMOUNT, gasUsed);

        assertEq(vault.balanceOf(address(inputToken), address(this)), MEDIUM_AMOUNT);
        assertEq(vault.getTotalDeposits(address(inputToken)), MEDIUM_AMOUNT);
    }

    /**
     * @notice Test vault deposit with large amount and measure gas
     */
    function test_VaultDeposit_LargeAmount_GasBenchmark() public {
        inputToken.approve(address(vault), LARGE_AMOUNT);

        uint gasBefore = gasleft();
        vault.deposit(address(inputToken), LARGE_AMOUNT, address(this));
        uint gasUsed = gasBefore - gasleft();

        recordGasBenchmark("DEPOSIT", "large_amount", LARGE_AMOUNT, gasUsed);

        assertEq(vault.balanceOf(address(inputToken), address(this)), LARGE_AMOUNT);
        assertEq(vault.getTotalDeposits(address(inputToken)), LARGE_AMOUNT);
    }

    // ============ WITHDRAWAL OPERATION TESTS WITH GAS BENCHMARKING ============

    /**
     * @notice Test vault withdrawal with small amount and measure gas
     */
    function test_VaultWithdraw_SmallAmount_GasBenchmark() public {
        // Setup: Deposit tokens first
        inputToken.approve(address(vault), SMALL_AMOUNT);
        vault.deposit(address(inputToken), SMALL_AMOUNT, address(this));

        uint balanceBefore = inputToken.balanceOf(address(this));

        // Measure gas for withdrawal
        uint gasBefore = gasleft();
        vault.withdraw(address(inputToken), SMALL_AMOUNT, address(this));
        uint gasUsed = gasBefore - gasleft();

        recordGasBenchmark("WITHDRAW", "small_amount", SMALL_AMOUNT, gasUsed);

        // Verify withdrawal
        assertEq(inputToken.balanceOf(address(this)), balanceBefore + SMALL_AMOUNT);
        assertEq(vault.balanceOf(address(inputToken), address(this)), 0);
        assertEq(vault.getTotalDeposits(address(inputToken)), 0);
    }

    /**
     * @notice Test vault withdrawal with medium amount and measure gas
     */
    function test_VaultWithdraw_MediumAmount_GasBenchmark() public {
        inputToken.approve(address(vault), MEDIUM_AMOUNT);
        vault.deposit(address(inputToken), MEDIUM_AMOUNT, address(this));

        uint balanceBefore = inputToken.balanceOf(address(this));

        uint gasBefore = gasleft();
        vault.withdraw(address(inputToken), MEDIUM_AMOUNT, address(this));
        uint gasUsed = gasBefore - gasleft();

        recordGasBenchmark("WITHDRAW", "medium_amount", MEDIUM_AMOUNT, gasUsed);

        assertEq(inputToken.balanceOf(address(this)), balanceBefore + MEDIUM_AMOUNT);
        assertEq(vault.balanceOf(address(inputToken), address(this)), 0);
    }

    /**
     * @notice Test vault withdrawal with large amount and measure gas
     */
    function test_VaultWithdraw_LargeAmount_GasBenchmark() public {
        inputToken.approve(address(vault), LARGE_AMOUNT);
        vault.deposit(address(inputToken), LARGE_AMOUNT, address(this));

        uint balanceBefore = inputToken.balanceOf(address(this));

        uint gasBefore = gasleft();
        vault.withdraw(address(inputToken), LARGE_AMOUNT, address(this));
        uint gasUsed = gasBefore - gasleft();

        recordGasBenchmark("WITHDRAW", "large_amount", LARGE_AMOUNT, gasUsed);

        assertEq(inputToken.balanceOf(address(this)), balanceBefore + LARGE_AMOUNT);
        assertEq(vault.balanceOf(address(inputToken), address(this)), 0);
    }

    // ============ INTEGRATED OPERATIONS WITH B3 TOKENLAUNCH ============

    /**
     * @notice Test integrated deposit via B3 addLiquidity operation
     */
    function test_IntegratedDeposit_via_AddLiquidity_GasBenchmark() public {
        vm.startPrank(user1);

        uint depositAmount = MEDIUM_AMOUNT;

        // Measure gas for integrated operation
        uint gasBefore = gasleft();
        b3.addLiquidity(depositAmount, 0); // minBondingTokens = 0 for test
        uint gasUsed = gasBefore - gasleft();

        recordGasBenchmark("INTEGRATED_DEPOSIT", "add_liquidity", depositAmount, gasUsed);

        // Verify vault received tokens through B3
        assertTrue(vault.balanceOf(address(inputToken), address(b3)) > 0);
        assertTrue(bondingToken.balanceOf(user1) > 0);

        vm.stopPrank();
    }

    /**
     * @notice Test integrated withdrawal via B3 removeLiquidity operation
     */
    function test_IntegratedWithdraw_via_RemoveLiquidity_GasBenchmark() public {
        vm.startPrank(user1);

        // Setup: Add liquidity first
        uint depositAmount = MEDIUM_AMOUNT;
        b3.addLiquidity(depositAmount, 0); // minBondingTokens = 0 for test
        uint bondingTokenBalance = bondingToken.balanceOf(user1);

        uint balanceBefore = inputToken.balanceOf(user1);

        // Measure gas for integrated withdrawal
        uint gasBefore = gasleft();
        b3.removeLiquidity(bondingTokenBalance, 0); // minInputTokens = 0 for test
        uint gasUsed = gasBefore - gasleft();

        recordGasBenchmark("INTEGRATED_WITHDRAW", "remove_liquidity", bondingTokenBalance, gasUsed);

        // Verify tokens were withdrawn from vault
        assertTrue(inputToken.balanceOf(user1) > balanceBefore);
        assertEq(bondingToken.balanceOf(user1), 0);

        vm.stopPrank();
    }

    // ============ EDGE CASE TESTS ============

    /**
     * @notice Test deposit with zero amount (should revert)
     */
    function test_VaultDeposit_ZeroAmount_ShouldRevert() public {
        // Test via this contract which is authorized
        inputToken.approve(address(vault), 0);

        vm.expectRevert("MockVault: amount is zero");
        vault.deposit(address(inputToken), 0, address(this));
    }

    /**
     * @notice Test withdrawal with zero amount (should revert)
     */
    function test_VaultWithdraw_ZeroAmount_ShouldRevert() public {
        vm.expectRevert("MockVault: amount is zero");
        vault.withdraw(address(inputToken), 0, address(this));
    }

    /**
     * @notice Test withdrawal without sufficient balance (should revert)
     */
    function test_VaultWithdraw_InsufficientBalance_ShouldRevert() public {
        vm.expectRevert("MockVault: insufficient balance");
        vault.withdraw(address(inputToken), MEDIUM_AMOUNT, address(this));
    }

    /**
     * @notice Test deposit with zero address token (should revert)
     */
    function test_VaultDeposit_ZeroAddressToken_ShouldRevert() public {
        vm.expectRevert("MockVault: token is zero address");
        vault.deposit(address(0), MEDIUM_AMOUNT, address(this));
    }

    /**
     * @notice Test deposit with zero address recipient (should revert)
     */
    function test_VaultDeposit_ZeroAddressRecipient_ShouldRevert() public {
        inputToken.approve(address(vault), MEDIUM_AMOUNT);

        vm.expectRevert("MockVault: recipient is zero address");
        vault.deposit(address(inputToken), MEDIUM_AMOUNT, address(0));
    }

    /**
     * @notice Test maximum amount deposit
     */
    function test_VaultDeposit_MaxAmount_GasBenchmark() public {
        // Mint maximum amount for test
        vm.prank(owner);
        inputToken.mint(address(this), MAX_AMOUNT);

        inputToken.approve(address(vault), MAX_AMOUNT);

        uint gasBefore = gasleft();
        vault.deposit(address(inputToken), MAX_AMOUNT, address(this));
        uint gasUsed = gasBefore - gasleft();

        recordGasBenchmark("DEPOSIT", "max_amount", MAX_AMOUNT, gasUsed);

        assertEq(vault.balanceOf(address(inputToken), address(this)), MAX_AMOUNT);
    }

    // ============ FUTURE AUTODOLA OPERATIONS (PLACEHOLDERS) ============

    /**
     * @notice Future test for AutoDola harvest operation
     * @dev Currently a placeholder - will be implemented when AutoDola harvest is available
     */
    function test_AutoDolaHarvest_GasBenchmark_PlaceholderForFuture() public {
        // This test is designed to fail initially as a reminder for future implementation
        // When AutoDola harvest functionality is added, this test should be updated

        vm.skip(true); // Skip this test until harvest functionality exists

        // Future implementation should:
        // 1. Setup AutoDola vault with yield-generating tokens
        // 2. Simulate time passage for yield generation
        // 3. Call harvest operation with gas measurement
        // 4. Verify yield was collected and distributed
        // 5. Record gas benchmark for harvest operation

        recordGasBenchmark("HARVEST", "future_autodola_harvest", 0, 0);
    }

    /**
     * @notice Future test for AutoDola compound operation
     * @dev Currently a placeholder - will be implemented when AutoDola compound is available
     */
    function test_AutoDolaCompound_GasBenchmark_PlaceholderForFuture() public {
        // This test is designed to fail initially as a reminder for future implementation
        // When AutoDola compound functionality is added, this test should be updated

        vm.skip(true); // Skip this test until compound functionality exists

        // Future implementation should:
        // 1. Setup AutoDola vault with compoundable rewards
        // 2. Accumulate rewards over time
        // 3. Call compound operation with gas measurement
        // 4. Verify rewards were reinvested correctly
        // 5. Record gas benchmark for compound operation

        recordGasBenchmark("COMPOUND", "future_autodola_compound", 0, 0);
    }

    // ============ AUTHORIZATION AND SECURITY TESTS ============

    /**
     * @notice Test unauthorized deposit attempt (should revert)
     */
    function test_VaultDeposit_Unauthorized_ShouldRevert() public {
        MockVault unauthorizedVault = new MockVault(owner);

        vm.startPrank(user1);
        inputToken.approve(address(unauthorizedVault), MEDIUM_AMOUNT);

        vm.expectRevert("Vault: unauthorized, only authorized clients");
        unauthorizedVault.deposit(address(inputToken), MEDIUM_AMOUNT, user1);

        vm.stopPrank();
    }

    /**
     * @notice Test unauthorized withdrawal attempt (should revert)
     */
    function test_VaultWithdraw_Unauthorized_ShouldRevert() public {
        MockVault unauthorizedVault = new MockVault(owner);

        vm.startPrank(user1);

        vm.expectRevert("Vault: unauthorized, only authorized clients");
        unauthorizedVault.withdraw(address(inputToken), MEDIUM_AMOUNT, user1);

        vm.stopPrank();
    }

    // ============ MULTIPLE USER SCENARIOS ============

    /**
     * @notice Test multiple deposits from authorized client (simulating multiple users via B3)
     */
    function test_MultipleUsers_Deposit_GasBenchmark() public {
        // First deposit (simulating user1 via B3)
        inputToken.approve(address(vault), MEDIUM_AMOUNT);
        uint gasBefore1 = gasleft();
        vault.deposit(address(inputToken), MEDIUM_AMOUNT, address(this));
        uint gasUsed1 = gasBefore1 - gasleft();

        // Second deposit (simulating user2 via B3)
        inputToken.approve(address(vault), MEDIUM_AMOUNT);
        uint gasBefore2 = gasleft();
        vault.deposit(address(inputToken), MEDIUM_AMOUNT, address(this));
        uint gasUsed2 = gasBefore2 - gasleft();

        recordGasBenchmark("MULTI_USER_DEPOSIT", "first_deposit", MEDIUM_AMOUNT, gasUsed1);
        recordGasBenchmark("MULTI_USER_DEPOSIT", "second_deposit", MEDIUM_AMOUNT, gasUsed2);

        // Verify both deposits - note that mock vault tracks balance by caller (authorized client)
        assertEq(vault.balanceOf(address(inputToken), address(this)), MEDIUM_AMOUNT * 2);
        assertEq(vault.getTotalDeposits(address(inputToken)), MEDIUM_AMOUNT * 2);
    }

    // ============ COMPLETE TEST SUITE RUNNER ============

    /**
     * @notice Run key tests and print comprehensive gas analysis
     */
    function test_ComprehensiveGasAnalysis() public {
        // Run individual tests that don't interfere with each other
        // Note: We create separate instances to avoid state interference

        // Test deposit operations
        inputToken.approve(address(vault), SMALL_AMOUNT);
        uint gasBefore = gasleft();
        vault.deposit(address(inputToken), SMALL_AMOUNT, address(this));
        uint gasUsed = gasBefore - gasleft();
        recordGasBenchmark("DEPOSIT", "small_analysis", SMALL_AMOUNT, gasUsed);

        // Clean slate for next test
        vault.withdraw(address(inputToken), SMALL_AMOUNT, address(this));

        // Test medium amount
        inputToken.approve(address(vault), MEDIUM_AMOUNT);
        gasBefore = gasleft();
        vault.deposit(address(inputToken), MEDIUM_AMOUNT, address(this));
        gasUsed = gasBefore - gasleft();
        recordGasBenchmark("DEPOSIT", "medium_analysis", MEDIUM_AMOUNT, gasUsed);

        // Test withdrawal
        gasBefore = gasleft();
        vault.withdraw(address(inputToken), MEDIUM_AMOUNT, address(this));
        gasUsed = gasBefore - gasleft();
        recordGasBenchmark("WITHDRAW", "medium_analysis", MEDIUM_AMOUNT, gasUsed);

        // Test integrated operations with fresh state
        vm.startPrank(user1);
        uint depositAmount = MEDIUM_AMOUNT;
        gasBefore = gasleft();
        b3.addLiquidity(depositAmount, 0);
        gasUsed = gasBefore - gasleft();
        recordGasBenchmark("INTEGRATED_DEPOSIT", "analysis", depositAmount, gasUsed);
        vm.stopPrank();

        // Print all benchmarks
        printGasBenchmarks();

        // Calculate averages for analysis
        uint depositGasTotal = 0;
        uint depositCount = 0;
        uint withdrawGasTotal = 0;
        uint withdrawCount = 0;

        for (uint i = 0; i < gasBenchmarks.length; i++) {
            if (keccak256(bytes(gasBenchmarks[i].operation)) == keccak256(bytes("DEPOSIT"))) {
                depositGasTotal += gasBenchmarks[i].gasUsed;
                depositCount++;
            } else if (keccak256(bytes(gasBenchmarks[i].operation)) == keccak256(bytes("WITHDRAW"))) {
                withdrawGasTotal += gasBenchmarks[i].gasUsed;
                withdrawCount++;
            }
        }

        if (depositCount > 0) {
            console.log("Average Deposit Gas: %s", depositGasTotal / depositCount);
        }
        if (withdrawCount > 0) {
            console.log("Average Withdraw Gas: %s", withdrawGasTotal / withdrawCount);
        }
    }
}
