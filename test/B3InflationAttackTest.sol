// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "@vault/mocks/MockVault.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title B3InflationAttackTest
 * @notice Tests validating system resilience against bonding token inflation attacks
 * @dev SECURITY-CRITICAL: Tests the scenario where an attacker inflates bonding token supply
 *      by directly calling mint() function and attempts to drain the vault through redemption
 *
 * CRITICAL SECURITY FINDING:
 * ========================
 * MockBondingToken.mint() has NO access control (anyone can call it)
 * Production bonding token MUST implement proper access control on mint() function
 * ONLY the Behodler3Tokenlaunch contract should be authorized to mint bonding tokens
 *
 * PROTECTION MECHANISM (Story 035 - Anti-Cantillon):
 * ==================================================
 * - VirtualL tracks legitimate bonding curve operations separately from totalSupply()
 * - External minting increases totalSupply but does NOT affect virtualL
 * - When external minting is detected (totalSupply > _lastKnownSupply):
 *   - Redemption switches to proportional mode: (bondingTokens / totalSupply) * vaultBalance
 *   - This ensures fair dilution (rebase effect) instead of Cantillon wealth extraction
 * - Normal curve operations continue using bonding curve formula
 * - Result: External minters get exactly their % of total supply, no more
 *
 * RECOMMENDATION:
 * ==============
 * Access control on mint() is CRITICAL - this is the primary defense
 * Virtual pair separation provides defense-in-depth but is NOT sufficient alone
 */
contract B3InflationAttackTest is Test {
    Behodler3Tokenlaunch public b3;
    MockVault public vault;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;

    address public owner = address(0x1);
    address public legitimateUser = address(0x2);
    address public attacker = address(0x3);

    // Virtual Liquidity Test Parameters
    uint256 public constant FUNDING_GOAL = 1_000_000 * 1e18; // 1M tokens
    uint256 public constant SEED_INPUT = 0; // Always zero with zero seed enforcement
    uint256 public constant DESIRED_AVG_PRICE = 0.9e18; // 0.9 (90% of final price)

    // Test amounts
    uint256 public constant LEGITIMATE_DEPOSIT = 100_000 * 1e18; // 100k input tokens
    uint256 public constant SMALL_INFLATION = 50_000 * 1e18; // 50k bonding tokens (smaller attack)

    event SecurityFinding(string message, uint256 value);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(address(this));

        // Deploy B3 contract
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
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);
        vm.stopPrank();

        // Setup test tokens
        inputToken.mint(legitimateUser, 10_000_000 * 1e18);
        inputToken.mint(attacker, 10_000_000 * 1e18);
    }

    // ============ ACCESS CONTROL VERIFICATION TESTS ============

    /**
     * @notice Test that external minting via bondingToken.mint() is UNPROTECTED
     * @dev CRITICAL FINDING: This test demonstrates the vulnerability in MockBondingToken
     *      Production bonding token MUST have access control restricting mint() to B3 contract only
     */
    function testExternalMintingIsUnprotected() public {
        uint256 balanceBefore = bondingToken.balanceOf(attacker);

        // Attacker directly calls bondingToken.mint() bypassing bonding curve
        vm.startPrank(attacker);
        bondingToken.mint(attacker, SMALL_INFLATION);
        vm.stopPrank();

        uint256 balanceAfter = bondingToken.balanceOf(attacker);

        // CRITICAL: This assertion PASSES, proving mint() is unprotected
        assertEq(
            balanceAfter - balanceBefore,
            SMALL_INFLATION,
            "External minting succeeded - CRITICAL VULNERABILITY if this is production code"
        );

        emit SecurityFinding("CRITICAL: bondingToken.mint() is publicly accessible", SMALL_INFLATION);
        console.log("SECURITY WARNING: bondingToken.mint() has no access control!");
        console.log("Attacker successfully minted", SMALL_INFLATION, "tokens without depositing input tokens");
    }

    /**
     * @notice Test that virtualL remains independent of external minting
     * @dev Confirms virtual pair architecture provides isolation from supply manipulation
     */
    function testVirtualLIndependenceFromInflation() public {
        // Add some legitimate liquidity first
        vm.startPrank(legitimateUser);
        inputToken.approve(address(b3), LEGITIMATE_DEPOSIT);
        b3.addLiquidity(LEGITIMATE_DEPOSIT, 0);
        vm.stopPrank();

        // Record virtualL before inflation
        uint256 virtualLBefore = b3.virtualL();
        uint256 totalSupplyBefore = bondingToken.totalSupply();

        console.log("\n=== BEFORE INFLATION ===");
        console.log("VirtualL:", virtualLBefore);
        console.log("TotalSupply:", totalSupplyBefore);

        // Attacker inflates supply
        vm.startPrank(attacker);
        bondingToken.mint(attacker, SMALL_INFLATION);
        vm.stopPrank();

        // Record virtualL after inflation
        uint256 virtualLAfter = b3.virtualL();
        uint256 totalSupplyAfter = bondingToken.totalSupply();

        console.log("\n=== AFTER INFLATION ===");
        console.log("VirtualL (unchanged):", virtualLAfter);
        console.log("TotalSupply (inflated):", totalSupplyAfter);

        // CRITICAL: virtualL should be UNCHANGED by external minting
        assertEq(virtualLAfter, virtualLBefore, "VirtualL must be independent of external minting");

        // After legitimate adds, totalSupply < virtualL (normal operation)
        // After external inflation, totalSupply can be closer to virtualL but still usually less
        // The divergence shows how much supply was illegitimately minted

        // Calculate divergence - may be positive or negative depending on amounts
        if (totalSupplyAfter > virtualLAfter) {
            uint256 divergence = totalSupplyAfter - virtualLAfter;
            console.log("Divergence (totalSupply > virtualL):", divergence);
            emit SecurityFinding("TotalSupply exceeded virtualL via inflation", divergence);
        } else {
            uint256 divergence = virtualLAfter - totalSupplyAfter;
            console.log("Divergence (virtualL > totalSupply):", divergence);
            emit SecurityFinding("VirtualL still exceeds totalSupply despite inflation", divergence);
        }
    }

    /**
     * @notice Test small-scale inflation attack with controlled redemption
     * @dev Uses smaller amounts to avoid vault drainage, demonstrating the attack vector
     */
    function testSmallInflationAttackScenario() public {
        // STEP 1: Legitimate user adds liquidity
        vm.startPrank(legitimateUser);
        inputToken.approve(address(b3), LEGITIMATE_DEPOSIT);
        uint256 legitimateBondingTokens = b3.addLiquidity(LEGITIMATE_DEPOSIT, 0);
        vm.stopPrank();

        uint256 vaultBalanceAfterDeposit = vault.balanceOf(address(inputToken), address(b3));
        console.log("\n=== STEP 1: Legitimate Liquidity Added ===");
        console.log("Vault balance:", vaultBalanceAfterDeposit);
        console.log("Legitimate bonding tokens:", legitimateBondingTokens);

        // STEP 2: Attacker inflates supply (smaller amount)
        vm.startPrank(attacker);
        bondingToken.mint(attacker, SMALL_INFLATION);
        vm.stopPrank();

        uint256 virtualL = b3.virtualL();
        uint256 totalSupply = bondingToken.totalSupply();
        console.log("\n=== STEP 2: Attacker Inflates Supply ===");
        console.log("VirtualL:", virtualL);
        console.log("TotalSupply:", totalSupply);
        console.log("Inflation amount:", SMALL_INFLATION);

        // STEP 3: Attacker attempts small redemption (10% of inflated tokens)
        uint256 redemptionAmount = SMALL_INFLATION / 10;

        vm.startPrank(attacker);
        uint256 balanceBefore = inputToken.balanceOf(attacker);
        uint256 inputTokensOut = b3.removeLiquidity(redemptionAmount, 0);
        uint256 balanceAfter = inputToken.balanceOf(attacker);
        vm.stopPrank();

        uint256 tokensReceived = balanceAfter - balanceBefore;

        console.log("\n=== STEP 3: Attacker Redemption ===");
        console.log("Redemption amount:", redemptionAmount);
        console.log("Tokens received:", tokensReceived);
        console.log("% of vault drained:", (tokensReceived * 100) / vaultBalanceAfterDeposit);

        // STEP 4: Verify vault has been partially drained
        uint256 vaultAfter = vault.balanceOf(address(inputToken), address(b3));
        console.log("\n=== STEP 4: Vault Impact ===");
        console.log("Vault remaining:", vaultAfter);
        console.log("Vault drained:", vaultBalanceAfterDeposit - vaultAfter);

        // Assertions
        assertGt(tokensReceived, 0, "Attacker received tokens from inflated supply");
        assertLt(vaultAfter, vaultBalanceAfterDeposit, "Vault was partially drained");

        // CRITICAL FINDING: The attacker successfully drained part of the vault
        // using tokens that were never deposited through the bonding curve
        emit SecurityFinding("Inflation attack allows partial vault drainage", tokensReceived);

        console.log("\n=== SECURITY FINDING ===");
        console.log("Attacker drained", (tokensReceived * 100) / vaultBalanceAfterDeposit, "% of vault");
        console.log("using tokens that were NEVER deposited through bonding curve");
        console.log("This demonstrates why access control on mint() is CRITICAL");
    }

    /**
     * @notice Test that totalSupply vs virtualL relationship is documented
     * @dev Provides clear documentation of the protection mechanism
     */
    function testTotalSupplyVsVirtualLDocumentation() public {
        // Initial state
        uint256 virtualLInitial = b3.virtualL();
        uint256 totalSupplyInitial = bondingToken.totalSupply();

        console.log("\n=== INITIAL STATE (No Liquidity) ===");
        console.log("VirtualL:", virtualLInitial);
        console.log("TotalSupply:", totalSupplyInitial);
        assertTrue(totalSupplyInitial == 0, "Initial totalSupply is zero");
        assertGt(virtualLInitial, 0, "Initial virtualL is positive (from setGoals)");

        // Add legitimate liquidity
        vm.startPrank(legitimateUser);
        inputToken.approve(address(b3), LEGITIMATE_DEPOSIT);
        uint256 bondingTokensReceived = b3.addLiquidity(LEGITIMATE_DEPOSIT, 0);
        vm.stopPrank();

        uint256 virtualLAfterAdd = b3.virtualL();
        uint256 totalSupplyAfterAdd = bondingToken.totalSupply();

        console.log("\n=== AFTER LEGITIMATE ADD ===");
        console.log("VirtualL decreased by:", virtualLInitial - virtualLAfterAdd);
        console.log("TotalSupply increased by:", totalSupplyAfterAdd - totalSupplyInitial);
        console.log("Bonding tokens minted:", bondingTokensReceived);

        // IMPORTANT: After add, virtualL > totalSupply (normal operation)
        // VirtualL started higher and decreased, totalSupply started at 0 and increased
        assertLt(totalSupplyAfterAdd, virtualLAfterAdd, "Normal operation: totalSupply < virtualL");

        // External inflation
        vm.startPrank(attacker);
        bondingToken.mint(attacker, SMALL_INFLATION);
        vm.stopPrank();

        uint256 virtualLAfterInflation = b3.virtualL();
        uint256 totalSupplyAfterInflation = bondingToken.totalSupply();

        console.log("\n=== AFTER EXTERNAL INFLATION ===");
        console.log("VirtualL (unchanged):", virtualLAfterInflation);
        console.log("TotalSupply (inflated):", totalSupplyAfterInflation);

        // Depending on inflation amount, totalSupply may still be less than virtualL
        // The key is that virtualL didn't change
        assertEq(virtualLAfterInflation, virtualLAfterAdd, "VirtualL unchanged by external minting");

        console.log("\n=== KEY SECURITY PROPERTIES ===");
        console.log("1. VirtualL tracks ONLY legitimate bonding curve operations");
        console.log("2. TotalSupply can be manipulated by external minting (if unprotected)");
        console.log("3. Redemption uses virtualL, providing partial isolation");
        console.log("4. ACCESS CONTROL on mint() is the PRIMARY defense");

        emit SecurityFinding("VirtualL separation provides defense-in-depth", 0);
    }

    /**
     * @notice Test that legitimate users are not blocked by inflation
     * @dev Verifies the system remains functional for honest users
     */
    function testLegitimateUsersNotBlockedByInflation() public {
        // Setup: legitimate user adds liquidity
        vm.startPrank(legitimateUser);
        inputToken.approve(address(b3), LEGITIMATE_DEPOSIT);
        uint256 legitimateBondingTokens = b3.addLiquidity(LEGITIMATE_DEPOSIT, 0);
        vm.stopPrank();

        // Attacker inflates supply (but doesn't redeem yet)
        vm.startPrank(attacker);
        bondingToken.mint(attacker, SMALL_INFLATION);
        vm.stopPrank();

        // Legitimate user should be able to redeem without issues
        vm.startPrank(legitimateUser);
        uint256 inputBalanceBefore = inputToken.balanceOf(legitimateUser);
        uint256 inputTokensOut = b3.removeLiquidity(legitimateBondingTokens, 0);
        uint256 inputBalanceAfter = inputToken.balanceOf(legitimateUser);
        vm.stopPrank();

        uint256 tokensReceived = inputBalanceAfter - inputBalanceBefore;

        // Verify legitimate user received tokens
        assertEq(tokensReceived, inputTokensOut, "User receives quoted amount");
        assertGt(inputTokensOut, 0, "Legitimate user receives input tokens");

        // Verify bonding tokens were burned
        assertEq(bondingToken.balanceOf(legitimateUser), 0, "Bonding tokens burned");

        console.log("\n=== LEGITIMATE USER REDEMPTION ===");
        console.log("Bonding tokens redeemed:", legitimateBondingTokens);
        console.log("Input tokens received:", inputTokensOut);
        console.log("Status: SUCCESS despite", SMALL_INFLATION, "inflated tokens in circulation");

        emit SecurityFinding("Legitimate operations work despite inflation", inputTokensOut);
    }

    /**
     * @notice Test multiple small redemptions by attacker
     * @dev Documents how repeated redemptions could gradually drain vault
     */
    function testMultipleSmallRedemptionsAttack() public {
        // Setup: legitimate user adds liquidity
        vm.startPrank(legitimateUser);
        inputToken.approve(address(b3), LEGITIMATE_DEPOSIT);
        b3.addLiquidity(LEGITIMATE_DEPOSIT, 0);
        vm.stopPrank();

        uint256 vaultBefore = vault.balanceOf(address(inputToken), address(b3));

        // Attacker inflates supply
        vm.startPrank(attacker);
        bondingToken.mint(attacker, SMALL_INFLATION);

        // Attacker makes multiple small redemptions
        uint256 redemptionSize = SMALL_INFLATION / 5; // 20% each
        uint256 totalDrained = 0;

        for (uint i = 0; i < 3; i++) {
            uint256 balBefore = inputToken.balanceOf(attacker);
            b3.removeLiquidity(redemptionSize, 0);
            uint256 balAfter = inputToken.balanceOf(attacker);
            uint256 drained = balAfter - balBefore;
            totalDrained += drained;
            console.log("Redemption", i + 1, "drained:", drained);
        }

        vm.stopPrank();

        uint256 vaultAfter = vault.balanceOf(address(inputToken), address(b3));
        uint256 percentDrained = (totalDrained * 100) / vaultBefore;

        console.log("\n=== MULTIPLE REDEMPTIONS ATTACK ===");
        console.log("Vault before:", vaultBefore);
        console.log("Vault after:", vaultAfter);
        console.log("Total drained:", totalDrained);
        console.log("Percent drained:", percentDrained, "%");

        // Document that repeated redemptions can drain vault
        assertGt(totalDrained, 0, "Attacker drained vault through multiple redemptions");
        assertLt(vaultAfter, vaultBefore, "Vault balance decreased");

        emit SecurityFinding("Multiple redemptions can drain vault", totalDrained);
    }
}
