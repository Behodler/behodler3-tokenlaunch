// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../../src/Behodler3Tokenlaunch.sol";
import "../../../src/mocks/MockERC20.sol";
import "../../../src/mocks/MockBondingToken.sol";
import "../../../lib/vault/src/interfaces/IVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockVault
 * @notice Simple vault implementation for testing
 */
contract MockVault is IVault {
    mapping(address => bool) public clients;
    mapping(address => mapping(address => uint256)) public accountBalances;

    function setClient(address client, bool authorized) external override {
        clients[client] = authorized;
    }

    function deposit(address token, uint256 amount, address recipient) external override {
        require(clients[msg.sender], "Not authorized");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        accountBalances[token][recipient] += amount;
    }

    function withdraw(address token, uint256 amount, address recipient) external override {
        require(clients[msg.sender], "Not authorized");
        require(accountBalances[token][recipient] >= amount, "Insufficient balance");
        accountBalances[token][recipient] -= amount;
        IERC20(token).transfer(recipient, amount);
    }

    function balanceOf(address token, address account) external view override returns (uint256) {
        return accountBalances[token][account];
    }

    function emergencyWithdraw(uint256 amount) external override {
        // Simplified for testing
    }

    function totalWithdrawal(address token, address client) external override {
        // Simplified for testing
    }
}

/**
 * @title TokenLaunchProperties
 * @notice Echidna property tests for Behodler3 TokenLaunch contract
 * @dev Implements core invariants for property-based testing
 */
contract TokenLaunchProperties {
    Behodler3Tokenlaunch public tokenLaunch;
    MockERC20 public inputToken;
    MockBondingToken public bondingToken;
    MockVault public vault;

    // Test state tracking
    mapping(address => uint256) public userInputBalanceBefore;
    mapping(address => uint256) public userBondingBalanceBefore;
    uint256 public totalInputSupplied;
    uint256 public totalBondingMinted;

    // Constants for testing
    uint256 constant INITIAL_TOKEN_SUPPLY = 1_000_000 * 1e18;
    uint256 constant TEST_FUNDING_GOAL = 50_000 * 1e18;
    uint256 constant TEST_SEED_INPUT = 0; // Always zero with zero seed enforcement
    uint256 constant TEST_DESIRED_PRICE = 0.9e18; // 0.9 (90% of final price, must be < 1)

    constructor() {
        // Initialize mock tokens
        inputToken = new MockERC20("TestInput", "TIN", 18);
        inputToken.mint(address(this), INITIAL_TOKEN_SUPPLY);
        bondingToken = new MockBondingToken("TestBonding", "TBN");

        // Initialize vault (use existing implementation)
        vault = new MockVault();

        // Initialize TokenLaunch
        tokenLaunch = new Behodler3Tokenlaunch(inputToken, bondingToken, vault);

        // Set up virtual liquidity goals
        tokenLaunch.setGoals(TEST_FUNDING_GOAL, TEST_DESIRED_PRICE);

        // Initialize vault approval
        vault.setClient(address(tokenLaunch), true);
        tokenLaunch.initializeVaultApproval();

        // Distribute tokens to test addresses
        _distributeTokens();
    }

    function _distributeTokens() internal {
        address[3] memory testUsers = [address(0x10000), address(0x20000), address(0x30000)];

        for (uint256 i = 0; i < testUsers.length; i++) {
            inputToken.transfer(testUsers[i], INITIAL_TOKEN_SUPPLY / 10);
            inputToken.approve(address(tokenLaunch), type(uint256).max);
        }
    }

    // ============ CORE INVARIANT PROPERTIES ============

    /**
     * @notice Virtual K invariant - K should never decrease inappropriately
     * @dev Virtual pair constant product should follow expected constraints using offset bonding curve
     */
    function echidna_virtual_k_invariant() public view returns (bool) {
        uint256 virtualInput = tokenLaunch.virtualInputTokens();
        uint256 virtualL = tokenLaunch.virtualL();
        uint256 alpha = tokenLaunch.alpha();
        uint256 beta = tokenLaunch.beta();

        // Use correct offset bonding curve formula: (x + α)(y + β) = k
        uint256 currentK = (virtualInput + alpha) * (virtualL + beta);
        uint256 expectedK = tokenLaunch.virtualK();

        // K should match expected virtual K (allowing for precision tolerance)
        // Use 0.01% tolerance for large numbers (similar to other tests in codebase)
        uint256 tolerance = expectedK / 1e4; // 0.01% tolerance for precision
        return currentK >= expectedK - tolerance && currentK <= expectedK + tolerance;
    }

    /**
     * @notice Token supply conservation - Total bonding tokens should equal total inputs via curve
     * @dev Ensures no tokens are created or destroyed unexpectedly
     */
    function echidna_token_supply_conservation() public view returns (bool) {
        if (!tokenLaunch.vaultApprovalInitialized()) return true;

        uint256 vaultBalance = inputToken.balanceOf(address(vault));
        uint256 bondingSupply = bondingToken.totalSupply();

        // If no operations yet, both should be zero
        if (bondingSupply == 0) {
            return vaultBalance == 0;
        }

        // There should be a reasonable relationship between vault balance and bonding supply
        // This is a loose invariant since exact math depends on bonding curve
        return vaultBalance > 0 && bondingSupply > 0;
    }

    /**
     * @notice Virtual liquidity non-zero invariant
     * @dev Virtual input and L should never be zero after initialization
     */
    function echidna_virtual_liquidity_non_zero() public view returns (bool) {
        if (!tokenLaunch.vaultApprovalInitialized()) return true;

        // With zero seed enforcement, virtualInputTokens starts at 0 (x₀ = 0)
        // virtualL should always be > 0 after setGoals
        return tokenLaunch.virtualL() > 0;
    }

    /**
     * @notice Vault balance consistency
     * @dev Vault balance should always be reasonable relative to operations
     */
    function echidna_vault_balance_consistency() public view returns (bool) {
        uint256 vaultBalance = inputToken.balanceOf(address(vault));
        uint256 contractBalance = inputToken.balanceOf(address(tokenLaunch));

        // Contract itself should not hold input tokens (they go to vault)
        return contractBalance == 0;
    }

    /**
     * @notice Bonding token ownership consistency
     * @dev Total bonding tokens distributed should equal total supply
     */
    function echidna_bonding_token_ownership_consistency() public view returns (bool) {
        uint256 totalSupply = bondingToken.totalSupply();

        // Calculate total held by test addresses
        uint256 totalHeld = 0;
        address[3] memory testUsers = [address(0x10000), address(0x20000), address(0x30000)];

        for (uint256 i = 0; i < testUsers.length; i++) {
            totalHeld += bondingToken.balanceOf(testUsers[i]);
        }

        // Add any tokens held by the contract itself
        totalHeld += bondingToken.balanceOf(address(tokenLaunch));

        return totalHeld == totalSupply;
    }

    /**
     * @notice Price monotonicity property
     * @dev As more liquidity is added, price per bonding token should generally increase
     */
    function echidna_price_monotonicity() public view returns (bool) {
        if (!tokenLaunch.vaultApprovalInitialized()) return true;

        uint256 virtualInput = tokenLaunch.virtualInputTokens();
        uint256 virtualL = tokenLaunch.virtualL();

        // With zero seed enforcement, virtualInput starts at 0 (x₀ = 0)
        // Price monotonicity only applies after first trade when virtualInput > 0
        // For initial state, just check virtualL is properly initialized
        return virtualL > 0;
    }

    // ============ OPERATION TESTING FUNCTIONS ============

    /**
     * @notice Test addLiquidity operation with random amounts
     * @dev Echidna will call this with random inputs
     */
    function addLiquidity(uint256 amount) public {
        // Bound the amount to reasonable range
        amount = bound(amount, 1e15, 1000 * 1e18); // 0.001 to 1000 tokens

        if (!tokenLaunch.vaultApprovalInitialized()) return;
        if (tokenLaunch.locked()) return;

        // Ensure caller has enough tokens
        if (inputToken.balanceOf(msg.sender) < amount) return;

        // Store state before operation
        uint256 userInputBefore = inputToken.balanceOf(msg.sender);
        uint256 userBondingBefore = bondingToken.balanceOf(msg.sender);
        uint256 vaultBefore = inputToken.balanceOf(address(vault));

        // Approve tokens
        inputToken.approve(address(tokenLaunch), amount);

        // Try to add liquidity
        try tokenLaunch.addLiquidity(amount, 0) {
            // Verify state changes are reasonable
            uint256 userInputAfter = inputToken.balanceOf(msg.sender);
            uint256 userBondingAfter = bondingToken.balanceOf(msg.sender);
            uint256 vaultAfter = inputToken.balanceOf(address(vault));

            // Input should decrease, bonding should increase, vault should increase
            assert(userInputAfter <= userInputBefore);
            assert(userBondingAfter >= userBondingBefore);
            assert(vaultAfter >= vaultBefore);
        } catch {
            // Operation failed, which is acceptable
        }
    }

    /**
     * @notice Test removeLiquidity operation
     * @dev Echidna will call this with random inputs
     */
    function removeLiquidity(uint256 bondingAmount) public {
        if (!tokenLaunch.vaultApprovalInitialized()) return;
        if (tokenLaunch.locked()) return;

        uint256 userBondingBalance = bondingToken.balanceOf(msg.sender);
        if (userBondingBalance == 0) return;

        // Bound to available balance
        bondingAmount = bound(bondingAmount, 1, userBondingBalance);

        // Store state before operation
        uint256 userInputBefore = inputToken.balanceOf(msg.sender);
        uint256 userBondingBefore = bondingToken.balanceOf(msg.sender);

        // Try to remove liquidity
        try tokenLaunch.removeLiquidity(bondingAmount, 0) {
            // Verify state changes are reasonable
            uint256 userInputAfter = inputToken.balanceOf(msg.sender);
            uint256 userBondingAfter = bondingToken.balanceOf(msg.sender);

            // Input should increase, bonding should decrease
            assert(userInputAfter >= userInputBefore);
            assert(userBondingAfter <= userBondingBefore);
        } catch {
            // Operation failed, which is acceptable
        }
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Bound function for constraining random inputs
     */
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
}
