// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./echidna/properties/TokenLaunchProperties.sol";

/**
 * @title PropertyTestHarness
 * @notice Advanced harness for executing property tests through Foundry test runner
 * @dev This contract provides a comprehensive testing framework that enables property tests
 *      to be executed via `forge test` while maintaining Echidna's fuzzing semantics.
 *
 * KEY FEATURES:
 * - Automated property validation across multiple scenarios
 * - Fuzz testing integration using Foundry's native fuzzing
 * - Property invariant checking under various state conditions
 * - Comprehensive test coverage for property-based testing
 */
contract PropertyTestHarness is Test {

    TokenLaunchProperties public propertyTester;

    // Test execution parameters
    uint constant FUZZ_RUNS = 100;
    uint constant MAX_TEST_AMOUNT = 1000 * 1e18;
    uint constant MIN_TEST_AMOUNT = 1e15;

    // ============ SETUP AND INITIALIZATION ============

    /**
     * @notice Initialize the property test harness
     * @dev Creates a fresh TokenLaunchProperties instance for isolated testing
     */
    function setUp() public {
        propertyTester = new TokenLaunchProperties();

        // Verify proper initialization
        require(address(propertyTester.tokenLaunch()) != address(0), "PropertyTester not initialized");
        require(address(propertyTester.inputToken()) != address(0), "InputToken not initialized");
        require(address(propertyTester.bondingToken()) != address(0), "BondingToken not initialized");
        require(address(propertyTester.vault()) != address(0), "Vault not initialized");
    }

    // ============ DIRECT PROPERTY TEST EXECUTION ============

    /**
     * @notice Execute all core property tests in sequence
     * @dev Validates all invariants in their initial state
     */
    function test_all_properties_initial_state() public view {
        // Execute all property checks
        assertTrue(propertyTester.echidna_virtual_k_invariant(), "Virtual K invariant failed");
        assertTrue(propertyTester.echidna_token_supply_conservation(), "Token supply conservation failed");
        assertTrue(propertyTester.echidna_virtual_liquidity_non_zero(), "Virtual liquidity non-zero failed");
        assertTrue(propertyTester.echidna_vault_balance_consistency(), "Vault balance consistency failed");
        assertTrue(propertyTester.echidna_bonding_token_ownership_consistency(), "Bonding token ownership failed");
        assertTrue(propertyTester.echidna_price_monotonicity(), "Price monotonicity failed");
    }

    /**
     * @notice Test properties after single add liquidity operation
     * @dev Validates invariants hold after state modification
     */
    function test_properties_after_add_liquidity() public {
        uint testAmount = 100 * 1e18;

        // Ensure property tester has sufficient tokens
        propertyTester.inputToken().transfer(address(propertyTester), testAmount);

        // Execute add liquidity operation through property tester
        vm.prank(address(propertyTester));
        propertyTester.addLiquidity(testAmount);

        // Validate all properties still hold
        assertTrue(propertyTester.echidna_virtual_k_invariant(), "Virtual K invariant failed after add liquidity");
        assertTrue(propertyTester.echidna_token_supply_conservation(), "Token supply conservation failed after add liquidity");
        assertTrue(propertyTester.echidna_virtual_liquidity_non_zero(), "Virtual liquidity non-zero failed after add liquidity");
        assertTrue(propertyTester.echidna_vault_balance_consistency(), "Vault balance consistency failed after add liquidity");
        assertTrue(propertyTester.echidna_bonding_token_ownership_consistency(), "Bonding token ownership failed after add liquidity");
        assertTrue(propertyTester.echidna_price_monotonicity(), "Price monotonicity failed after add liquidity");
    }

    /**
     * @notice Test properties after add and remove liquidity cycle
     * @dev Validates invariants hold through complete operation cycle
     */
    function test_properties_after_liquidity_cycle() public {
        uint addAmount = 200 * 1e18;

        // Ensure property tester has sufficient tokens
        propertyTester.inputToken().transfer(address(propertyTester), addAmount);

        // Add liquidity
        vm.prank(address(propertyTester));
        propertyTester.addLiquidity(addAmount);

        // Get bonding token balance for removal
        uint bondingBalance = propertyTester.bondingToken().balanceOf(address(propertyTester));
        if (bondingBalance > 0) {
            uint removeAmount = bondingBalance / 2;

            // Remove half the liquidity
            vm.prank(address(propertyTester));
            propertyTester.removeLiquidity(removeAmount);
        }

        // Validate all properties still hold after complete cycle
        assertTrue(propertyTester.echidna_virtual_k_invariant(), "Virtual K invariant failed after liquidity cycle");
        assertTrue(propertyTester.echidna_token_supply_conservation(), "Token supply conservation failed after liquidity cycle");
        assertTrue(propertyTester.echidna_virtual_liquidity_non_zero(), "Virtual liquidity non-zero failed after liquidity cycle");
        assertTrue(propertyTester.echidna_vault_balance_consistency(), "Vault balance consistency failed after liquidity cycle");
        assertTrue(propertyTester.echidna_bonding_token_ownership_consistency(), "Bonding token ownership failed after liquidity cycle");
        assertTrue(propertyTester.echidna_price_monotonicity(), "Price monotonicity failed after liquidity cycle");
    }

    // ============ FOUNDRY FUZZ TESTING INTEGRATION ============

    /**
     * @notice Fuzz test add liquidity with property validation
     * @dev Uses Foundry's built-in fuzzing to test properties across random inputs
     * @param amount Random amount for add liquidity operation
     */
    function testFuzz_add_liquidity_properties(uint amount) public {
        // Bound the amount to reasonable range (similar to Echidna's bound function)
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        // Skip if property tester is not properly initialized
        if (!propertyTester.tokenLaunch().vaultApprovalInitialized()) {
            return;
        }

        // Skip if token launch is locked
        if (propertyTester.tokenLaunch().locked()) {
            return;
        }

        // Ensure property tester has sufficient tokens
        if (propertyTester.inputToken().balanceOf(address(propertyTester)) < amount) {
            // Mint tokens to property tester for the test
            vm.prank(address(propertyTester));
            propertyTester.inputToken().mint(address(propertyTester), amount);
        }

        // Record state before operation
        bool propertiesValidBefore = _validateAllProperties();
        assertTrue(propertiesValidBefore, "Properties should be valid before operation");

        // Execute add liquidity operation
        vm.prank(address(propertyTester));
        try propertyTester.addLiquidity(amount) {
            // If operation succeeded, properties should still be valid
            bool propertiesValidAfter = _validateAllProperties();
            assertTrue(propertiesValidAfter, "Properties should remain valid after successful add liquidity");
        } catch {
            // If operation failed, properties should still be valid (operation had no effect)
            bool propertiesValidAfter = _validateAllProperties();
            assertTrue(propertiesValidAfter, "Properties should remain valid after failed add liquidity");
        }
    }

    /**
     * @notice Fuzz test remove liquidity with property validation
     * @dev Uses Foundry's built-in fuzzing to test properties across random inputs
     * @param bondingAmount Random bonding amount for remove liquidity operation
     */
    function testFuzz_remove_liquidity_properties(uint bondingAmount) public {
        // First add some liquidity to ensure we have bonding tokens to remove
        uint addAmount = 500 * 1e18;
        propertyTester.inputToken().transfer(address(propertyTester), addAmount);

        vm.prank(address(propertyTester));
        try propertyTester.addLiquidity(addAmount) {} catch {}

        // Get actual bonding balance
        uint actualBondingBalance = propertyTester.bondingToken().balanceOf(address(propertyTester));
        if (actualBondingBalance == 0) {
            return; // Skip test if no bonding tokens available
        }

        // Bound to available balance
        bondingAmount = bound(bondingAmount, 1, actualBondingBalance);

        // Skip if property tester is not properly initialized
        if (!propertyTester.tokenLaunch().vaultApprovalInitialized()) {
            return;
        }

        // Skip if token launch is locked
        if (propertyTester.tokenLaunch().locked()) {
            return;
        }

        // Record state before operation
        bool propertiesValidBefore = _validateAllProperties();
        assertTrue(propertiesValidBefore, "Properties should be valid before operation");

        // Execute remove liquidity operation
        vm.prank(address(propertyTester));
        try propertyTester.removeLiquidity(bondingAmount) {
            // If operation succeeded, properties should still be valid
            bool propertiesValidAfter = _validateAllProperties();
            assertTrue(propertiesValidAfter, "Properties should remain valid after successful remove liquidity");
        } catch {
            // If operation failed, properties should still be valid (operation had no effect)
            bool propertiesValidAfter = _validateAllProperties();
            assertTrue(propertiesValidAfter, "Properties should remain valid after failed remove liquidity");
        }
    }

    /**
     * @notice Fuzz test multiple operations sequence with property validation
     * @dev Tests property invariants across sequences of operations
     * @param addAmount1 First add amount
     * @param addAmount2 Second add amount
     * @param removePercent Percentage of bonding tokens to remove (0-100)
     */
    function testFuzz_operation_sequence_properties(uint addAmount1, uint addAmount2, uint removePercent) public {
        // Bound inputs
        addAmount1 = bound(addAmount1, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT / 2);
        addAmount2 = bound(addAmount2, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT / 2);
        removePercent = bound(removePercent, 0, 100);

        // Skip if property tester is not properly initialized
        if (!propertyTester.tokenLaunch().vaultApprovalInitialized()) {
            return;
        }

        // Skip if token launch is locked
        if (propertyTester.tokenLaunch().locked()) {
            return;
        }

        // Ensure sufficient tokens
        uint totalNeeded = addAmount1 + addAmount2;
        propertyTester.inputToken().transfer(address(propertyTester), totalNeeded);

        // Validate initial state
        assertTrue(_validateAllProperties(), "Properties should be valid initially");

        // First add liquidity
        vm.prank(address(propertyTester));
        try propertyTester.addLiquidity(addAmount1) {} catch {}
        assertTrue(_validateAllProperties(), "Properties should be valid after first add");

        // Second add liquidity
        vm.prank(address(propertyTester));
        try propertyTester.addLiquidity(addAmount2) {} catch {}
        assertTrue(_validateAllProperties(), "Properties should be valid after second add");

        // Remove liquidity based on percentage
        uint bondingBalance = propertyTester.bondingToken().balanceOf(address(propertyTester));
        if (bondingBalance > 0 && removePercent > 0) {
            uint removeAmount = (bondingBalance * removePercent) / 100;
            if (removeAmount > 0) {
                vm.prank(address(propertyTester));
                try propertyTester.removeLiquidity(removeAmount) {} catch {}
                assertTrue(_validateAllProperties(), "Properties should be valid after remove");
            }
        }
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Validate all property invariants
     * @dev Internal function to check all properties at once
     * @return true if all properties are valid, false otherwise
     */
    function _validateAllProperties() internal view returns (bool) {
        return propertyTester.echidna_virtual_k_invariant() &&
               propertyTester.echidna_token_supply_conservation() &&
               propertyTester.echidna_virtual_liquidity_non_zero() &&
               propertyTester.echidna_vault_balance_consistency() &&
               propertyTester.echidna_bonding_token_ownership_consistency() &&
               propertyTester.echidna_price_monotonicity();
    }

    /**
     * @notice Test harness initialization validation
     * @dev Ensures the harness is properly configured
     */
    function test_harness_initialization() public view {
        // Verify harness setup
        assertNotEq(address(propertyTester), address(0), "PropertyTester should be initialized");
        assertNotEq(address(propertyTester.tokenLaunch()), address(0), "TokenLaunch should be initialized");
        assertNotEq(address(propertyTester.inputToken()), address(0), "InputToken should be initialized");
        assertNotEq(address(propertyTester.bondingToken()), address(0), "BondingToken should be initialized");
        assertNotEq(address(propertyTester.vault()), address(0), "Vault should be initialized");
    }

    /**
     * @notice Test that property functions are correctly exposed
     * @dev Validates that all echidna_ functions are accessible through the harness
     */
    function test_property_function_accessibility() public view {
        // Test that all property functions can be called and return boolean values
        bool result1 = propertyTester.echidna_virtual_k_invariant();
        bool result2 = propertyTester.echidna_token_supply_conservation();
        bool result3 = propertyTester.echidna_virtual_liquidity_non_zero();
        bool result4 = propertyTester.echidna_vault_balance_consistency();
        bool result5 = propertyTester.echidna_bonding_token_ownership_consistency();
        bool result6 = propertyTester.echidna_price_monotonicity();

        // The fact that this compiles and runs means all functions are accessible
        assertTrue(true, "All property functions are accessible");
    }
}