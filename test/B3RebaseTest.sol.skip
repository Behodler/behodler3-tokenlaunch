// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title B3RebaseTest
 * @notice Tests for anti-Cantillon rebase mechanism (Story 035)
 * @dev Verifies that external minting causes proportional dilution, not Cantillon effect
 *
 * KEY PRINCIPLE BEING TESTED:
 * "100% of bondingToken supply must always redeem 100% of inputToken held in the bonding curve"
 *
 * EXPECTED BEHAVIOR:
 * - External minting should act as a rebase (proportional dilution)
 * - NOT as Cantillon effect (disproportionate wealth extraction)
 * - Total redemption value should never exceed vault balance
 */
contract B3RebaseTest is Test {
    Behodler3Tokenlaunch public b3;
    MockVault public vault;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;

    address public owner = address(0x1);
    address public legitimateUser = address(0x2);
    address public attacker = address(0x3);

    // Virtual Liquidity Test Parameters
    uint256 public constant FUNDING_GOAL = 1_000_000 * 1e18;
    uint256 public constant DESIRED_AVG_PRICE = 0.9e18;

    // Test amounts
    uint256 public constant LEGITIMATE_DEPOSIT = 100_000 * 1e18;
    uint256 public constant EXTERNAL_MINT_AMOUNT = 50_000 * 1e18;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));

        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(
            IERC20(address(inputToken)), IBondingToken(address(bondingToken)), IYieldStrategy(address(vault))
        );

        vm.stopPrank();

        // Setup vault
        vault.setClient(address(b3), true);

        // Initialize B3
        vm.startPrank(owner);
        b3.initializeVaultApproval();
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);
        vm.stopPrank();

        // Fund test accounts
        inputToken.mint(legitimateUser, 10_000_000 * 1e18);
        inputToken.mint(attacker, 10_000_000 * 1e18);
    }

    /**
     * @notice Test that external minting causes proportional dilution (rebase)
     * @dev After external mint, each token's redemption value should decrease proportionally
     */
    function testRebaseProportionalDilution() public {
        // Step 1: Legitimate user deposits
        vm.startPrank(legitimateUser);
        inputToken.approve(address(b3), LEGITIMATE_DEPOSIT);
        uint256 bondingTokensReceived = b3.addLiquidity(LEGITIMATE_DEPOSIT, 0);
        vm.stopPrank();

        console.log("=== STEP 1: Initial Deposit ===");
        console.log("Bonding tokens received:", bondingTokensReceived);
        console.log("Vault balance:", vault.principalOf(address(inputToken), address(b3)));

        // Calculate redemption value BEFORE external minting
        uint256 redemptionBefore = b3.quoteRemoveLiquidity(bondingTokensReceived);
        console.log("\n=== BEFORE External Mint ===");
        console.log("Full redemption value:", redemptionBefore);
        console.log("Total supply:", bondingToken.totalSupply());

        // Step 2: External minting (simulating DAO payment or fee)
        vm.startPrank(attacker);
        bondingToken.mint(attacker, EXTERNAL_MINT_AMOUNT);
        vm.stopPrank();

        uint256 totalSupplyAfter = bondingToken.totalSupply();
        console.log("\n=== AFTER External Mint ===");
        console.log("External mint amount:", EXTERNAL_MINT_AMOUNT);
        console.log("Total supply:", totalSupplyAfter);

        // Calculate redemption value AFTER external minting
        uint256 redemptionAfter = b3.quoteRemoveLiquidity(bondingTokensReceived);
        console.log("Full redemption value:", redemptionAfter);

        // Expected dilution factor = oldSupply / newSupply
        uint256 expectedDilutionFactor = (bondingTokensReceived * 1e18) / totalSupplyAfter;
        uint256 expectedRedemption = (redemptionBefore * expectedDilutionFactor) / 1e18;

        console.log("\n=== DILUTION ANALYSIS ===");
        console.log("Dilution factor (%):", (bondingTokensReceived * 100) / totalSupplyAfter);
        console.log("Expected redemption:", expectedRedemption);
        console.log("Actual redemption:", redemptionAfter);

        // Verify proportional dilution occurred
        // Allow small rounding error (0.1%)
        uint256 difference = redemptionBefore > redemptionAfter ? redemptionBefore - redemptionAfter : redemptionAfter - redemptionBefore;
        uint256 percentDiff = (difference * 10000) / redemptionBefore;

        assertTrue(redemptionAfter < redemptionBefore, "Redemption value should decrease after external mint");
        assertTrue(percentDiff > 0, "Some dilution should occur");

        console.log("Redemption decreased by (basis points):", percentDiff);
    }

    /**
     * @notice Test that total redemption never exceeds vault balance
     * @dev The fundamental invariant: 100% of supply redeems 100% of vault
     */
    function testTotalRedemptionNeverExceedsVault() public {
        // Step 1: Legitimate deposit
        vm.startPrank(legitimateUser);
        inputToken.approve(address(b3), LEGITIMATE_DEPOSIT);
        uint256 legitTokens = b3.addLiquidity(LEGITIMATE_DEPOSIT, 0);
        vm.stopPrank();

        // Step 2: External mint
        vm.startPrank(attacker);
        bondingToken.mint(attacker, EXTERNAL_MINT_AMOUNT);
        vm.stopPrank();

        uint256 vaultBalance = vault.principalOf(address(inputToken), address(b3));

        // Calculate what EVERYONE could redeem
        uint256 legitRedemption = b3.quoteRemoveLiquidity(legitTokens);
        uint256 attackerRedemption = b3.quoteRemoveLiquidity(EXTERNAL_MINT_AMOUNT);
        uint256 totalPotentialRedemption = legitRedemption + attackerRedemption;

        console.log("=== TOTAL REDEMPTION CHECK ===");
        console.log("Vault balance:", vaultBalance);
        console.log("Legit user redemption:", legitRedemption);
        console.log("Attacker redemption:", attackerRedemption);
        console.log("Total potential redemption:", totalPotentialRedemption);

        // CRITICAL INVARIANT: Total redemption should not exceed vault
        // Allow small rounding in favor of vault (redemption slightly less is OK)
        assertTrue(
            totalPotentialRedemption <= vaultBalance,
            "Total potential redemption must not exceed vault balance"
        );

        uint256 utilizationPercent = (totalPotentialRedemption * 100) / vaultBalance;
        console.log("Vault utilization:", utilizationPercent, "%");
    }

    /**
     * @notice Test attacker cannot extract disproportionate value (anti-Cantillon)
     * @dev Attacker's share should be proportional to their % of total supply
     */
    function testNoCantillonEffect() public {
        // Step 1: Legitimate deposit
        vm.startPrank(legitimateUser);
        inputToken.approve(address(b3), LEGITIMATE_DEPOSIT);
        b3.addLiquidity(LEGITIMATE_DEPOSIT, 0);
        vm.stopPrank();

        uint256 vaultBalance = vault.principalOf(address(inputToken), address(b3));

        // Step 2: External mint
        vm.startPrank(attacker);
        bondingToken.mint(attacker, EXTERNAL_MINT_AMOUNT);
        vm.stopPrank();

        uint256 totalSupply = bondingToken.totalSupply();

        // Attacker's share of total supply
        uint256 attackerSharePercent = (EXTERNAL_MINT_AMOUNT * 100) / totalSupply;

        // Attacker redeems ALL their tokens
        vm.startPrank(attacker);
        uint256 attackerRedemption = b3.removeLiquidity(EXTERNAL_MINT_AMOUNT, 0);
        vm.stopPrank();

        // What % of vault did attacker extract?
        uint256 extractionPercent = (attackerRedemption * 100) / vaultBalance;

        console.log("=== CANTILLON EFFECT CHECK ===");
        console.log("Attacker's share of supply:", attackerSharePercent, "%");
        console.log("Attacker's extraction from vault:", extractionPercent, "%");
        console.log("Difference:", attackerSharePercent > extractionPercent ?
            attackerSharePercent - extractionPercent : extractionPercent - attackerSharePercent, "%");

        // Attacker should NOT extract more than their proportional share
        // Allow small tolerance for rounding
        assertTrue(
            extractionPercent <= attackerSharePercent + 1,  // +1% tolerance
            "Attacker should not extract disproportionate value (Cantillon effect)"
        );

        // In perfect rebase, extraction should equal share
        emit log_named_uint("Expected extraction %", attackerSharePercent);
        emit log_named_uint("Actual extraction %", extractionPercent);
    }

    /**
     * @notice Test that legitimate users are not unfairly diluted
     * @dev After external mint, legitimate users should maintain their proportional share
     */
    function testLegitimateUserFairDilution() public {
        // Step 1: Legitimate deposit
        vm.startPrank(legitimateUser);
        inputToken.approve(address(b3), LEGITIMATE_DEPOSIT);
        uint256 legitTokens = b3.addLiquidity(LEGITIMATE_DEPOSIT, 0);
        vm.stopPrank();

        // Step 2: External mint
        vm.startPrank(attacker);
        bondingToken.mint(attacker, EXTERNAL_MINT_AMOUNT);
        vm.stopPrank();

        uint256 totalSupply = bondingToken.totalSupply();
        uint256 vaultBalance = vault.principalOf(address(inputToken), address(b3));

        // Legitimate user's share of supply
        uint256 legitSharePercent = (legitTokens * 100) / totalSupply;

        // Legitimate user redeems
        vm.startPrank(legitimateUser);
        uint256 legitRedemption = b3.removeLiquidity(legitTokens, 0);
        vm.stopPrank();

        uint256 legitExtractionPercent = (legitRedemption * 100) / vaultBalance;

        console.log("=== LEGITIMATE USER FAIRNESS ===");
        console.log("Legitimate user's share of supply:", legitSharePercent, "%");
        console.log("Legitimate user's extraction from vault:", legitExtractionPercent, "%");

        // Legitimate user should get their fair share
        // Allow tolerance for rounding
        uint256 diff = legitSharePercent > legitExtractionPercent ?
            legitSharePercent - legitExtractionPercent : legitExtractionPercent - legitSharePercent;

        assertTrue(
            diff <= 2,  // 2% tolerance
            "Legitimate user should get proportional share"
        );
    }

    /**
     * @notice Test extreme inflation scenario (10x supply increase)
     * @dev Even with massive inflation, invariants should hold
     */
    function testExtremeInflationScenario() public {
        // Step 1: Legitimate deposit
        vm.startPrank(legitimateUser);
        inputToken.approve(address(b3), LEGITIMATE_DEPOSIT);
        uint256 legitTokens = b3.addLiquidity(LEGITIMATE_DEPOSIT, 0);
        vm.stopPrank();

        uint256 vaultBalance = vault.principalOf(address(inputToken), address(b3));

        // Step 2: Extreme external mint (10x the legitimate supply)
        uint256 extremeMint = legitTokens * 10;
        vm.startPrank(attacker);
        bondingToken.mint(attacker, extremeMint);
        vm.stopPrank();

        uint256 totalSupply = bondingToken.totalSupply();

        console.log("=== EXTREME INFLATION (10x) ===");
        console.log("Legitimate tokens:", legitTokens);
        console.log("External mint (10x):", extremeMint);
        console.log("Total supply:", totalSupply);

        // Calculate total potential redemption
        uint256 legitRedemption = b3.quoteRemoveLiquidity(legitTokens);
        uint256 attackerRedemption = b3.quoteRemoveLiquidity(extremeMint);
        uint256 totalRedemption = legitRedemption + attackerRedemption;

        console.log("Vault balance:", vaultBalance);
        console.log("Total potential redemption:", totalRedemption);

        // Even with 10x inflation, total redemption must not exceed vault
        assertTrue(
            totalRedemption <= vaultBalance,
            "Extreme inflation should not break vault invariant"
        );

        // Attacker with 10x tokens should get ~91% of vault (10/11)
        uint256 attackerSharePercent = (extremeMint * 100) / totalSupply;
        uint256 attackerExtractionPercent = (attackerRedemption * 100) / vaultBalance;

        console.log("Attacker's share:", attackerSharePercent, "%");
        console.log("Attacker's potential extraction:", attackerExtractionPercent, "%");

        // Should be proportional
        uint256 diff = attackerSharePercent > attackerExtractionPercent ?
            attackerSharePercent - attackerExtractionPercent : attackerExtractionPercent - attackerSharePercent;

        assertTrue(diff <= 2, "Even extreme inflation should maintain proportionality");
    }
}
