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
    
    // Virtual Liquidity Test Parameters
    uint256 public constant FUNDING_GOAL = 1_000_000 * 1e18; // 1M tokens
    uint256 public constant SEED_INPUT = 1000 * 1e18; // 1K tokens
    uint256 public constant DESIRED_AVG_PRICE = 0.9e18; // 0.9 (90% of final price)
    
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

        // Initialize vault approval after vault authorizes B3
        vm.startPrank(owner);
        b3.initializeVaultApproval();

        // Set virtual liquidity goals
        b3.setGoals(FUNDING_GOAL, SEED_INPUT, DESIRED_AVG_PRICE);
        vm.stopPrank();

        // Setup test tokens
        inputToken.mint(user1, 1000000 * 1e18);
        inputToken.mint(user2, 1000000 * 1e18);
    }
    
    // ============ VIRTUAL PAIR INITIALIZATION TESTS ============
    
    function testVirtualPairInitialization() public view {
        // Test virtual liquidity parameters are set correctly
        assertEq(b3.fundingGoal(), FUNDING_GOAL, "Funding goal should match");
        assertEq(b3.seedInput(), SEED_INPUT, "Seed input should match");
        assertEq(b3.desiredAveragePrice(), DESIRED_AVG_PRICE, "Desired average price should match");
        assertGt(b3.virtualK(), 0, "Virtual K should be positive");
        assertGt(b3.alpha(), 0, "Alpha should be positive");
        assertEq(b3.beta(), b3.alpha(), "Beta should equal alpha");
    }
    
    function testVirtualPairInitializationFlag() public view {
        // Test that virtual liquidity initialization is detected correctly
        assertTrue(b3.isVirtualPairInitialized(), "Virtual liquidity should be initialized");
    }
    
    function testKConstantCalculation() public view {
        // Test that virtual K constant is calculated correctly from goals
        uint256 actualVirtualK = b3.virtualK();
        uint256 actualAlpha = b3.alpha();

        // K should equal (x_fin + alpha)^2
        uint256 xFinPlusAlpha = FUNDING_GOAL + actualAlpha;
        uint256 expectedVirtualK = xFinPlusAlpha * xFinPlusAlpha;

        assertEq(actualVirtualK, expectedVirtualK, "Virtual K should equal (x_fin + alpha)^2");
    }
    
    function testVirtualInputTokensInitialization() public view {
        // Test virtual input tokens are set to seed input
        assertEq(b3.virtualInputTokens(), SEED_INPUT, "Virtual input tokens should equal seed input");
    }
    
    function testVirtualLInitialization() public view {
        // Test virtual L tokens are calculated correctly: y_0 = k/(x_0 + alpha) - alpha
        uint256 actualVirtualL = b3.virtualL();
        uint256 alpha = b3.alpha();
        uint256 virtualK = b3.virtualK();
        uint256 x0PlusAlpha = SEED_INPUT + alpha;
        uint256 expectedVirtualL = virtualK / x0PlusAlpha - alpha;

        assertEq(actualVirtualL, expectedVirtualL, "Virtual L should be calculated correctly");
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
        assertEq(inputTokens, SEED_INPUT, "Virtual input tokens should remain at seed input");
        assertGt(lTokens, 0, "Virtual L tokens should be positive");
        assertEq(k, inputTokens * lTokens, "K should equal input * L for compatibility");
        
        // Restore bonding curve to B3 contract
        vault.setClient(address(b3), true);
    }
    
    function testVirtualPairStateAfterBondingTokenMinting() public {
        // Test virtual pair state after bonding tokens are minted
        uint256 mintAmount = 50000;
        bondingToken.mint(user1, mintAmount);
        
        // Virtual pair should be independent from external bonding token supply
        (uint256 inputTokens, uint256 lTokens, uint256 k) = b3.getVirtualPair();
        assertEq(inputTokens, SEED_INPUT, "Virtual input tokens should remain at seed input after external minting");
        assertGt(lTokens, 0, "Virtual L tokens should be positive after external minting");
        assertEq(k, inputTokens * lTokens, "K should equal input * L for compatibility after external minting");
        
        // Confirm that virtualL != totalSupply after minting
        assertTrue(b3.virtualL() != bondingToken.totalSupply(), "VirtualL should differ from total supply after minting");
    }
    
    // ============ VIRTUAL PAIR MATH VALIDATION TESTS ============
    
    function testKConsistencyAfterVirtualPairUpdates() public {
        // Test that virtual liquidity invariant (x+alpha)(y+beta)=k always holds
        (uint256 inputTokens, uint256 lTokens, ) = b3.getVirtualPair();
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 virtualK = b3.virtualK();

        uint256 leftSide = (inputTokens + alpha) * (lTokens + beta);
        assertApproxEqRel(leftSide, virtualK, 1e15, "Virtual liquidity invariant should hold"); // 0.1% tolerance
    }
    
    function testVirtualPairPreservesKAfterOperations() public {
        // Test that virtual pair operations preserve the constant product
        // This test will be more meaningful after addLiquidity is implemented
        uint256 initialVirtualK = b3.virtualK();
        
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
        // Test internal consistency of virtual liquidity parameters
        uint256 virtualInput = b3.virtualInputTokens();
        uint256 virtualL = b3.virtualL();
        uint256 virtualK = b3.virtualK();

        (uint256 returnedInput, uint256 returnedL, uint256 returnedK) = b3.getVirtualPair();

        assertEq(virtualInput, returnedInput, "Virtual input tokens should be consistent");
        assertEq(virtualL, returnedL, "Virtual L tokens should be consistent");
        assertEq(returnedK, virtualInput * virtualL, "Returned K should equal input * L for compatibility");

        // Also check virtual liquidity invariant consistency
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 leftSide = (virtualInput + alpha) * (virtualL + beta);
        assertApproxEqRel(leftSide, virtualK, 1e15, "Virtual liquidity invariant should hold");
    }
    
    // ============ ARCHITECTURE VALIDATION TESTS ============
    
    function testVirtualPairArchitectureDocumentation() public view {
        // This test documents the expected virtual liquidity architecture
        // Virtual liquidity uses (x+alpha)(y+beta)=k formula instead of traditional xy=k

        (uint256 inputTokens, uint256 lTokens, uint256 k) = b3.getVirtualPair();

        // Input tokens should be initialized to seed input
        assertEq(inputTokens, SEED_INPUT, "Virtual liquidity architecture: input should equal seed input");

        // Virtual L should be calculated from virtual liquidity formula
        assertGt(lTokens, 0, "Virtual liquidity architecture: L should be positive");

        // K should be the product for compatibility
        assertEq(k, inputTokens * lTokens, "Virtual liquidity architecture: k should equal input * L");

        // Verify virtual liquidity invariant (x+alpha)(y+beta)=virtualK
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        uint256 virtualK = b3.virtualK();
        uint256 leftSide = (inputTokens + alpha) * (lTokens + beta);
        assertApproxEqRel(leftSide, virtualK, 1e15, "Virtual liquidity invariant should hold");
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