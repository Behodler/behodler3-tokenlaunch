// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./echidna/properties/TokenLaunchProperties.sol";

/**
 * @title PropertyTestBridge
 * @notice Foundry-compatible bridge for Echidna property tests
 * @dev This contract acts as a bridge between Foundry's test runner and Echidna property tests,
 *      enabling unified execution via `forge test` while maintaining property test functionality.
 *
 * CRITICAL ARCHITECTURE:
 * - Inherits from both Foundry's Test contract and Echidna property contract
 * - Wraps echidna_ functions as Foundry-compatible test_ functions
 * - Maintains property test semantics while enabling Foundry discovery
 * - Allows single-command execution: `forge test` runs all test types
 * - Resolves function signature conflicts through composition rather than inheritance
 */
contract PropertyTestBridge is Test {

    // Use composition instead of inheritance to avoid function signature conflicts
    TokenLaunchProperties public propertyTester;

    // ============ FOUNDRY SETUP ============

    /**
     * @notice Foundry setup function - called before each test
     * @dev Initializes the property test environment for Foundry execution
     */
    function setUp() public {
        // Create a fresh TokenLaunchProperties instance for isolated testing
        propertyTester = new TokenLaunchProperties();

        // Verify that property test environment is properly initialized
        require(address(propertyTester.tokenLaunch()) != address(0), "TokenLaunch not initialized");
        require(address(propertyTester.inputToken()) != address(0), "InputToken not initialized");
        require(address(propertyTester.bondingToken()) != address(0), "BondingToken not initialized");
        require(address(propertyTester.vault()) != address(0), "Vault not initialized");
    }

    // ============ PROPERTY TEST BRIDGES ============

    /**
     * @notice Bridge for virtual K invariant property test
     * @dev Wraps echidna_virtual_k_invariant as Foundry-compatible test
     */
    function test_virtual_k_invariant() public view {
        bool result = propertyTester.echidna_virtual_k_invariant();
        assertTrue(result, "Virtual K invariant violated: K should remain consistent");
    }

    /**
     * @notice Bridge for token supply conservation property test
     * @dev Wraps echidna_token_supply_conservation as Foundry-compatible test
     */
    function test_token_supply_conservation() public view {
        bool result = propertyTester.echidna_token_supply_conservation();
        assertTrue(result, "Token supply conservation violated: Supply mismatch detected");
    }

    /**
     * @notice Bridge for virtual liquidity non-zero property test
     * @dev Wraps echidna_virtual_liquidity_non_zero as Foundry-compatible test
     */
    function test_virtual_liquidity_non_zero() public view {
        bool result = propertyTester.echidna_virtual_liquidity_non_zero();
        assertTrue(result, "Virtual liquidity non-zero invariant violated: Virtual liquidity is zero");
    }

    /**
     * @notice Bridge for vault balance consistency property test
     * @dev Wraps echidna_vault_balance_consistency as Foundry-compatible test
     */
    function test_vault_balance_consistency() public view {
        bool result = propertyTester.echidna_vault_balance_consistency();
        assertTrue(result, "Vault balance consistency violated: Balance inconsistency detected");
    }

    /**
     * @notice Bridge for bonding token ownership consistency property test
     * @dev Wraps echidna_bonding_token_ownership_consistency as Foundry-compatible test
     */
    function test_bonding_token_ownership_consistency() public view {
        bool result = propertyTester.echidna_bonding_token_ownership_consistency();
        assertTrue(result, "Bonding token ownership consistency violated: Ownership mismatch detected");
    }

    /**
     * @notice Bridge for price monotonicity property test
     * @dev Wraps echidna_price_monotonicity as Foundry-compatible test
     */
    function test_price_monotonicity() public view {
        bool result = propertyTester.echidna_price_monotonicity();
        assertTrue(result, "Price monotonicity violated: Price behavior is incorrect");
    }

    // ============ INTEGRATION TESTING FUNCTIONS ============

    /**
     * @notice Test add liquidity operation through bridge
     * @dev Tests property contract's addLiquidity function via Foundry
     */
    function test_addLiquidity_integration() public {
        // Use a reasonable test amount
        uint testAmount = 100 * 1e18;

        // PropertyTester already has tokens from its constructor, verify it has enough
        uint currentBalance = propertyTester.inputToken().balanceOf(address(propertyTester));
        if (currentBalance < testAmount) {
            // If not enough, mint more tokens to the propertyTester
            vm.prank(address(propertyTester));
            propertyTester.inputToken().mint(address(propertyTester), testAmount);
        }

        // Store state before operation
        uint balanceBefore = propertyTester.inputToken().balanceOf(address(propertyTester));
        uint bondingBefore = propertyTester.bondingToken().balanceOf(address(propertyTester));

        // Call the property test's addLiquidity function
        vm.prank(address(propertyTester));
        propertyTester.addLiquidity(testAmount);

        // Verify state changes are reasonable
        uint balanceAfter = propertyTester.inputToken().balanceOf(address(propertyTester));
        uint bondingAfter = propertyTester.bondingToken().balanceOf(address(propertyTester));

        // Basic sanity checks
        assertLe(balanceAfter, balanceBefore, "Input balance should not increase unexpectedly");

        // Verify all property invariants still hold after operation
        assertTrue(propertyTester.echidna_virtual_k_invariant(), "K invariant violated after addLiquidity");
        assertTrue(propertyTester.echidna_vault_balance_consistency(), "Vault consistency violated after addLiquidity");
    }

    /**
     * @notice Test remove liquidity operation through bridge
     * @dev Tests property contract's removeLiquidity function via Foundry
     */
    function test_removeLiquidity_integration() public {
        // First add some liquidity to have something to remove
        uint addAmount = 50 * 1e18;

        // Ensure property tester has sufficient tokens
        uint currentBalance = propertyTester.inputToken().balanceOf(address(propertyTester));
        if (currentBalance < addAmount) {
            vm.prank(address(propertyTester));
            propertyTester.inputToken().mint(address(propertyTester), addAmount);
        }

        vm.prank(address(propertyTester));
        propertyTester.addLiquidity(addAmount);

        // Now test remove liquidity
        uint bondingBalance = propertyTester.bondingToken().balanceOf(address(propertyTester));
        if (bondingBalance > 0) {
            uint removeAmount = bondingBalance / 2; // Remove half

            // Store state before operation
            uint inputBefore = propertyTester.inputToken().balanceOf(address(propertyTester));
            uint bondingBefore = propertyTester.bondingToken().balanceOf(address(propertyTester));

            // Call the property test's removeLiquidity function
            vm.prank(address(propertyTester));
            propertyTester.removeLiquidity(removeAmount);

            // Verify state changes are reasonable
            uint inputAfter = propertyTester.inputToken().balanceOf(address(propertyTester));
            uint bondingAfter = propertyTester.bondingToken().balanceOf(address(propertyTester));

            // Basic sanity checks
            assertLe(bondingAfter, bondingBefore, "Bonding balance should not increase unexpectedly");

            // Verify all property invariants still hold after operation
            assertTrue(propertyTester.echidna_virtual_k_invariant(), "K invariant violated after removeLiquidity");
            assertTrue(propertyTester.echidna_vault_balance_consistency(), "Vault consistency violated after removeLiquidity");
        }
    }

    // ============ UTILITY FUNCTIONS FOR BRIDGE ============

    /**
     * @notice Test that all property functions are accessible
     * @dev Ensures the bridge properly exposes all property functions
     */
    function test_property_functions_accessible() public view {
        // Verify all echidna_ functions are accessible through composition
        assertTrue(true, "If this compiles, property functions are accessible");

        // Test a sample of composed functions exist by calling them
        propertyTester.echidna_virtual_k_invariant();
        propertyTester.echidna_token_supply_conservation();
        propertyTester.echidna_virtual_liquidity_non_zero();
        propertyTester.echidna_vault_balance_consistency();
        propertyTester.echidna_bonding_token_ownership_consistency();
        propertyTester.echidna_price_monotonicity();
    }

    /**
     * @notice Test that composed state is properly initialized
     * @dev Ensures property test state is correctly accessible through composition
     */
    function test_composed_state_initialization() public view {
        // Verify composed contract state is properly initialized
        assertNotEq(address(propertyTester.tokenLaunch()), address(0), "TokenLaunch should be initialized");
        assertNotEq(address(propertyTester.inputToken()), address(0), "InputToken should be initialized");
        assertNotEq(address(propertyTester.bondingToken()), address(0), "BondingToken should be initialized");
        assertNotEq(address(propertyTester.vault()), address(0), "Vault should be initialized");

        // Verify that token balances reflect proper initialization
        // (Constants are internal, so we test the effects instead)
        uint propertyTesterBalance = propertyTester.inputToken().balanceOf(address(propertyTester));
        assertGt(propertyTesterBalance, 0, "Property tester should have initial token supply");
    }
}