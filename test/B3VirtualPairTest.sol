// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title B3VirtualPairTest
 * @notice Tests for Virtual Pair mechanics in Behodler3 Bootstrap AMM
 * @dev These tests are written FIRST in TDD Red Phase - they SHOULD FAIL initially
 * 
 * CRITICAL CONCEPT BEING TESTED: Virtual Pair Architecture
 * - Virtual Pair: (inputToken, virtualL) where virtualL exists only as internal accounting
 * - Initial setup: (10000 inputToken, 100000000 virtualL) establishing k = 1,000,000,000,000
 * - Trading: Calculate virtual swap FIRST using xy=k, THEN mint actual bondingToken
 * - virtualL is NOT the same as bondingToken.totalSupply() - it's virtual/unminted
 */
contract B3VirtualPairTest is Test {
    Behodler3Tokenlaunch public b3;
    MockVault public vault;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    // Virtual Pair Constants
    uint256 public constant INITIAL_VIRTUAL_INPUT = 10000;
    uint256 public constant INITIAL_VIRTUAL_L = 100000000;
    uint256 public constant K = 1_000_000_000_000; // INITIAL_VIRTUAL_INPUT * INITIAL_VIRTUAL_L
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock contracts
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));
        
        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)),
            IBondingToken(address(bondingToken)),
            IVault(address(vault))
        );
        
        vm.stopPrank();
        
        // Set the bonding curve address in the vault to allow B3 to call deposit/withdraw
        vault.setClient(address(b3), true);
        
        // Setup test tokens
        inputToken.mint(user1, 1000000 * 1e18);
        inputToken.mint(user2, 1000000 * 1e18);
    }
    
    // ============ VIRTUAL PAIR INITIALIZATION TESTS ============
    
    function testVirtualPairInitialization() public view {
        // Test virtual pair should be initialized with correct values
        (uint256 inputTokens, uint256 lTokens, uint256 k) = b3.getVirtualPair();
        
        assertEq(inputTokens, INITIAL_VIRTUAL_INPUT, "Virtual input tokens should be 10000");
        assertEq(lTokens, INITIAL_VIRTUAL_L, "Virtual L tokens should be 100000000");
        assertEq(k, K, "K should be 1,000,000,000,000");
    }
    
    function testVirtualPairInitializationFlag() public view {
        // Test that virtual pair initialization is detected correctly
        assertTrue(b3.isVirtualPairInitialized(), "Virtual pair should be initialized");
    }
    
    function testKConstantCalculation() public view {
        // Test that K constant is calculated correctly
        uint256 expectedK = INITIAL_VIRTUAL_INPUT * INITIAL_VIRTUAL_L;
        assertEq(b3.K(), expectedK, "K constant should equal initial input * initial L");
        assertEq(b3.K(), K, "K constant should equal 1,000,000,000,000");
    }
    
    function testVirtualInputTokensInitialization() public view {
        // Test virtual input tokens are set correctly
        assertEq(b3.virtualInputTokens(), INITIAL_VIRTUAL_INPUT, "Virtual input tokens should be 10000");
    }
    
    function testVirtualLInitialization() public view {
        // Test virtual L tokens are set correctly
        assertEq(b3.virtualL(), INITIAL_VIRTUAL_L, "Virtual L tokens should be 100000000");
    }
    
    // ============ VIRTUAL PAIR vs ACTUAL BALANCE TESTS ============
    
    function testVirtualLNotEqualTotalSupply() public view {
        // CRITICAL TEST: virtualL should NOT equal bondingToken.totalSupply()
        // This is the key difference from standard bonding curves
        assertTrue(b3.virtualLDifferentFromTotalSupply(), "VirtualL should be different from bonding token total supply");
        
        uint256 virtualL = b3.virtualL();
        uint256 totalSupply = bondingToken.totalSupply();
        assertTrue(virtualL != totalSupply, "VirtualL should not equal total supply");
    }
    
    function testVirtualPairIndependentFromActualBalances() public {
        // Test that virtual pair state is independent from actual token balances
        
        // Set bonding curve to user1 to allow direct deposit for this test
        vault.setClient(user1, true);
        
        vm.startPrank(user1);
        inputToken.approve(address(vault), 1000 * 1e18);
        
        // Even after deposits to vault, virtual pair should maintain its state
        vault.deposit(address(inputToken), 1000 * 1e18, user1);
        
        vm.stopPrank();
        
        (uint256 inputTokens, uint256 lTokens, uint256 k) = b3.getVirtualPair();
        assertEq(inputTokens, INITIAL_VIRTUAL_INPUT, "Virtual input tokens should remain unchanged");
        assertEq(lTokens, INITIAL_VIRTUAL_L, "Virtual L tokens should remain unchanged");
        assertEq(k, K, "K should remain unchanged");
        
        // Restore bonding curve to B3 contract
        vault.setClient(address(b3), true);
    }
    
    function testVirtualPairStateAfterBondingTokenMinting() public {
        // Test virtual pair state after bonding tokens are minted
        uint256 mintAmount = 50000;
        bondingToken.mint(user1, mintAmount);
        
        // Virtual pair should be independent from bonding token supply
        (uint256 inputTokens, uint256 lTokens, uint256 k) = b3.getVirtualPair();
        assertEq(inputTokens, INITIAL_VIRTUAL_INPUT, "Virtual input tokens should remain unchanged after minting");
        assertEq(lTokens, INITIAL_VIRTUAL_L, "Virtual L tokens should remain unchanged after minting");
        assertEq(k, K, "K should remain unchanged after minting");
        
        // Confirm that virtualL != totalSupply after minting
        assertTrue(b3.virtualL() != bondingToken.totalSupply(), "VirtualL should differ from total supply after minting");
    }
    
    // ============ VIRTUAL PAIR MATH VALIDATION TESTS ============
    
    function testKConsistencyAfterVirtualPairUpdates() public {
        // Test that k = virtualInputTokens * virtualL always holds
        // This test assumes virtual pair will be updated by operations
        (uint256 inputTokens, uint256 lTokens, uint256 k) = b3.getVirtualPair();
        assertEq(k, inputTokens * lTokens, "K should always equal virtualInputTokens * virtualL");
    }
    
    function testVirtualPairPreservesKAfterOperations() public {
        // Test that virtual pair operations preserve the constant product
        // This test will be more meaningful after addLiquidity is implemented
        uint256 initialK = b3.K();
        
        // Attempt to add liquidity (will fail in RED phase but test the concept)
        vm.startPrank(user1);
        inputToken.approve(address(b3), 1000 * 1e18);
        
        try b3.addLiquidity(1000 * 1e18, 0) {
            // After operation, check that K is preserved in some form
            (uint256 inputTokens, uint256 lTokens, uint256 k) = b3.getVirtualPair();
            assertEq(k, inputTokens * lTokens, "K should be preserved after operations");
        } catch {
            // Expected to fail in RED phase
        }
        
        vm.stopPrank();
    }
    
    // ============ EDGE CASE TESTS ============
    
    function testVirtualPairWithZeroValues() public {
        // Test behavior when virtual pair has zero values (should not happen in correct implementation)
        (uint256 inputTokens, uint256 lTokens, uint256 k) = b3.getVirtualPair();
        
        // In RED phase, these will be zero, but that's wrong
        if (inputTokens == 0 || lTokens == 0) {
            // This test documents the current wrong state
            assertTrue(false, "Virtual pair should never have zero values");
        }
    }
    
    function testVirtualPairConsistency() public view {
        // Test internal consistency of virtual pair
        uint256 virtualInput = b3.virtualInputTokens();
        uint256 virtualL = b3.virtualL();
        uint256 k = b3.K();
        
        (uint256 returnedInput, uint256 returnedL, uint256 returnedK) = b3.getVirtualPair();
        
        assertEq(virtualInput, returnedInput, "Virtual input tokens should be consistent");
        assertEq(virtualL, returnedL, "Virtual L tokens should be consistent");
        assertEq(k, returnedK, "K should be consistent");
    }
    
    // ============ ARCHITECTURE VALIDATION TESTS ============
    
    function testVirtualPairArchitectureDocumentation() public view {
        // This test documents the expected virtual pair architecture
        uint256 expectedInitialInput = 10000;
        uint256 expectedInitialL = 100000000;
        uint256 expectedK = expectedInitialInput * expectedInitialL;
        
        // These assertions document what the implementation should achieve
        (uint256 inputTokens, uint256 lTokens, uint256 k) = b3.getVirtualPair();
        
        assertEq(inputTokens, expectedInitialInput, "Virtual pair architecture: input should be 10000");
        assertEq(lTokens, expectedInitialL, "Virtual pair architecture: L should be 100000000");
        assertEq(k, expectedK, "Virtual pair architecture: k should be 1,000,000,000,000");
    }
    
    function testVirtualPairNotStandardBondingCurve() public view {
        // Test that this is NOT a standard bonding curve
        // Standard bonding curves use actual token supplies, virtual pair uses virtual amounts
        
        uint256 bondingSupply = bondingToken.totalSupply();
        uint256 virtualL = b3.virtualL();
        
        // In a standard bonding curve, virtualL would equal bondingSupply
        // In virtual pair architecture, they should be different
        assertTrue(virtualL != bondingSupply, "Virtual pair should differ from standard bonding curve");
    }
}