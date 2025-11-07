// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/Pauser.sol";
import "../src/mocks/MockBondingToken.sol";
import "@vault/mocks/MockERC20.sol";
import "@vault/mocks/MockVault.sol";

/**
 * @title PauserTest
 * @notice Comprehensive tests for emergency pause functionality
 * @dev Tests Pauser contract and Behodler pause integration
 */
contract PauserTest is Test {
    Behodler3Tokenlaunch public b3;
    Pauser public pauser;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;
    MockERC20 public eyeToken;
    MockVault public vault;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public attacker = address(0x4);

    // Test constants
    uint256 constant FUNDING_GOAL = 1_000_000 * 1e18;
    uint256 constant DESIRED_AVG_PRICE = 0.9e18;
    uint256 constant DEFAULT_EYE_BURN_AMOUNT = 1000 * 1e18;
    uint256 constant INITIAL_EYE_BALANCE = 10_000 * 1e18;

    // Events to test
    event PauseTriggered(address indexed triggeredBy, uint256 eyeBurned);
    event UnpauseTriggered(address indexed triggeredBy);
    event ConfigUpdated(uint256 newEyeBurnAmount, address newBehodlerContract);
    event PauserUpdated(address indexed oldPauser, address indexed newPauser);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        bondingToken = new MockBondingToken("BondingToken", "BOND");
        inputToken = new MockERC20("TestToken", "TEST", 18);
        eyeToken = new MockERC20("EYE", "EYE", 18);
        vault = new MockVault(owner);

        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(inputToken, bondingToken, vault);

        // Setup vault authorization
        vault.setClient(address(b3), true);
        b3.initializeVaultApproval();

        // Setup virtual liquidity
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Deploy Pauser contract
        pauser = new Pauser(address(eyeToken));

        // Configure Pauser with B3 address
        pauser.config(DEFAULT_EYE_BURN_AMOUNT, address(b3));

        // Set Pauser in B3
        b3.setPauser(address(pauser));

        // Mint EYE tokens to users
        eyeToken.mint(user1, INITIAL_EYE_BALANCE);
        eyeToken.mint(user2, INITIAL_EYE_BALANCE);
        eyeToken.mint(attacker, INITIAL_EYE_BALANCE);

        vm.stopPrank();
    }

    // ============ PAUSER CONTRACT TESTS ============

    function test_Pauser_Deployment() public view {
        assertEq(address(pauser.eyeToken()), address(eyeToken), "EYE token should be set");
        assertEq(pauser.eyeBurnAmount(), DEFAULT_EYE_BURN_AMOUNT, "Default burn amount should be 1000 EYE");
        assertEq(pauser.behodlerContract(), address(b3), "Behodler contract should be set");
        assertEq(pauser.owner(), owner, "Owner should be set correctly");
    }

    function test_Pauser_Config_UpdatesParameters() public {
        uint256 newBurnAmount = 500 * 1e18;
        address newBehodler = address(0x999);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ConfigUpdated(newBurnAmount, newBehodler);
        pauser.config(newBurnAmount, newBehodler);

        assertEq(pauser.eyeBurnAmount(), newBurnAmount, "Burn amount should be updated");
        assertEq(pauser.behodlerContract(), newBehodler, "Behodler contract should be updated");
    }

    function test_Pauser_Config_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        pauser.config(500 * 1e18, address(0x999));
    }

    function test_Pauser_Config_RevertsIfZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Pauser: Behodler contract cannot be zero address");
        pauser.config(500 * 1e18, address(0));
    }

    function test_Pauser_Config_RevertsIfZeroBurnAmount() public {
        vm.prank(owner);
        vm.expectRevert("Pauser: EYE burn amount must be positive");
        pauser.config(0, address(b3));
    }

    // ============ PAUSE MECHANISM TESTS ============

    function test_Pauser_Pause_SucceedsWithSufficientEYE() public {
        // User1 approves Pauser to spend EYE
        vm.prank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);

        // Verify contract is not paused
        assertFalse(b3.paused(), "Contract should not be paused initially");

        // User1 triggers pause
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit PauseTriggered(user1, DEFAULT_EYE_BURN_AMOUNT);
        pauser.pause();

        // Verify contract is now paused
        assertTrue(b3.paused(), "Contract should be paused after pause()");

        // Verify EYE tokens were burned (sent to dead address)
        assertEq(
            eyeToken.balanceOf(address(0xdead)), DEFAULT_EYE_BURN_AMOUNT, "EYE should be burned to dead address"
        );
        assertEq(
            eyeToken.balanceOf(user1),
            INITIAL_EYE_BALANCE - DEFAULT_EYE_BURN_AMOUNT,
            "User1 balance should decrease by burn amount"
        );
    }

    function test_Pauser_Pause_RevertsWithoutApproval() public {
        // User1 does NOT approve Pauser

        vm.prank(user1);
        vm.expectRevert();
        pauser.pause();
    }

    function test_Pauser_Pause_RevertsWithInsufficientBalance() public {
        // Create a user with insufficient balance
        address poorUser = address(0x5);
        vm.prank(owner);
        eyeToken.mint(poorUser, 100 * 1e18); // Only 100 EYE

        vm.prank(poorUser);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);

        vm.prank(poorUser);
        vm.expectRevert();
        pauser.pause();
    }

    function test_Pauser_Pause_RevertsIfBehodlerNotConfigured() public {
        // Deploy a fresh Pauser without config
        vm.prank(owner);
        Pauser freshPauser = new Pauser(address(eyeToken));

        vm.prank(user1);
        eyeToken.approve(address(freshPauser), DEFAULT_EYE_BURN_AMOUNT);

        vm.prank(user1);
        vm.expectRevert("Pauser: Behodler contract not configured");
        freshPauser.pause();
    }

    function test_Pauser_Pause_MultipleUsers_CanTrigger() public {
        // First pause by user1
        vm.prank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        vm.prank(user1);
        pauser.pause();
        assertTrue(b3.paused(), "Should be paused");

        // Unpause
        vm.prank(owner);
        pauser.unpause();
        assertFalse(b3.paused(), "Should be unpaused");

        // Second pause by user2
        vm.prank(user2);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        vm.prank(user2);
        pauser.pause();
        assertTrue(b3.paused(), "Should be paused again");
    }

    // ============ UNPAUSE TESTS ============

    function test_Pauser_Unpause_SucceedsAsOwner() public {
        // First pause the contract
        vm.prank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        vm.prank(user1);
        pauser.pause();

        assertTrue(b3.paused(), "Contract should be paused");

        // Owner unpauses
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit UnpauseTriggered(owner);
        pauser.unpause();

        assertFalse(b3.paused(), "Contract should be unpaused");
    }

    function test_Pauser_Unpause_RevertsIfNotOwner() public {
        // First pause the contract
        vm.prank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        vm.prank(user1);
        pauser.pause();

        // User1 tries to unpause (should fail)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        pauser.unpause();
    }

    function test_Pauser_Unpause_RevertsIfBehodlerNotConfigured() public {
        // Deploy a fresh Pauser without config
        vm.prank(owner);
        Pauser freshPauser = new Pauser(address(eyeToken));

        vm.prank(owner);
        vm.expectRevert("Pauser: Behodler contract not configured");
        freshPauser.unpause();
    }

    // ============ BEHODLER PAUSE/UNPAUSE TESTS ============

    function test_Behodler_SetPauser_UpdatesAddress() public {
        address newPauser = address(0x888);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit PauserUpdated(address(pauser), newPauser);
        b3.setPauser(newPauser);

        assertEq(b3.pauser(), newPauser, "Pauser should be updated");
    }

    function test_Behodler_SetPauser_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        b3.setPauser(address(0x888));
    }

    function test_Behodler_SetPauser_RevertsIfZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("B3: Pauser cannot be zero address");
        b3.setPauser(address(0));
    }

    function test_Behodler_Pause_OnlyPauserCanCall() public {
        // Pauser contract calls pause
        vm.prank(address(pauser));
        b3.pause();
        assertTrue(b3.paused(), "Contract should be paused");
    }

    function test_Behodler_Pause_RevertsIfNotPauser() public {
        vm.prank(user1);
        vm.expectRevert("B3: Caller is not the pauser");
        b3.pause();
    }

    function test_Behodler_Unpause_OnlyOwnerCanCall() public {
        // First pause
        vm.prank(address(pauser));
        b3.pause();

        // Owner unpauses
        vm.prank(owner);
        b3.unpause();
        assertFalse(b3.paused(), "Contract should be unpaused");
    }

    function test_Behodler_Unpause_RevertsIfNotOwner() public {
        // First pause
        vm.prank(address(pauser));
        b3.pause();

        // User tries to unpause
        vm.prank(user1);
        vm.expectRevert("B3: Caller is not owner or pauser");
        b3.unpause();
    }

    // ============ INTEGRATION TESTS - OPERATIONS BLOCKED WHEN PAUSED ============

    function test_Behodler_AddLiquidity_BlockedWhenPaused() public {
        // Setup: add initial liquidity before pausing
        vm.startPrank(owner);
        inputToken.mint(user1, 10_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(user1);
        inputToken.approve(address(b3), 10_000 * 1e18);
        vm.stopPrank();

        // Pause the contract
        vm.prank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        vm.prank(user1);
        pauser.pause();

        // Try to add liquidity (should fail)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        b3.addLiquidity(1000 * 1e18, 0);
    }

    function test_Behodler_RemoveLiquidity_BlockedWhenPaused() public {
        // Setup: add liquidity first
        vm.startPrank(owner);
        inputToken.mint(user1, 10_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(user1);
        inputToken.approve(address(b3), 10_000 * 1e18);
        uint256 bondingTokens = b3.addLiquidity(5000 * 1e18, 0);
        vm.stopPrank();

        // Pause the contract
        vm.prank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        vm.prank(user1);
        pauser.pause();

        // Try to remove liquidity (should fail)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        b3.removeLiquidity(bondingTokens, 0);
    }

    function test_Behodler_Operations_WorkAfterUnpause() public {
        // Setup liquidity
        vm.startPrank(owner);
        inputToken.mint(user1, 10_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(user1);
        inputToken.approve(address(b3), 10_000 * 1e18);
        vm.stopPrank();

        // Pause
        vm.prank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        vm.prank(user1);
        pauser.pause();

        // Verify paused
        assertTrue(b3.paused(), "Should be paused");

        // Unpause
        vm.prank(owner);
        pauser.unpause();

        // Verify unpaused
        assertFalse(b3.paused(), "Should be unpaused");

        // Operations should work now
        vm.prank(user1);
        uint256 bondingTokens = b3.addLiquidity(1000 * 1e18, 0);
        assertTrue(bondingTokens > 0, "Should receive bonding tokens");

        vm.prank(user1);
        uint256 inputTokensOut = b3.removeLiquidity(bondingTokens / 2, 0);
        assertTrue(inputTokensOut > 0, "Should receive input tokens");
    }

    // ============ SECURITY TESTS ============

    function test_Security_UnauthorizedPauseAttempts_Fail() public {
        // Direct pause attempt by non-pauser
        vm.prank(attacker);
        vm.expectRevert("B3: Caller is not the pauser");
        b3.pause();

        assertFalse(b3.paused(), "Contract should not be paused");
    }

    function test_Security_OnlyOwnerCanUnpause() public {
        // Pause the contract
        vm.prank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        vm.prank(user1);
        pauser.pause();

        // Attacker tries to unpause through Pauser
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        pauser.unpause();

        // Attacker tries to unpause B3 directly
        vm.prank(attacker);
        vm.expectRevert("B3: Caller is not owner or pauser");
        b3.unpause();

        assertTrue(b3.paused(), "Contract should remain paused");
    }

    function test_Security_PauseRequiresEYEBurning() public {
        // Verify EYE burning is mandatory
        uint256 initialDeadBalance = eyeToken.balanceOf(address(0xdead));

        vm.prank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);

        vm.prank(user1);
        pauser.pause();

        uint256 finalDeadBalance = eyeToken.balanceOf(address(0xdead));

        assertEq(
            finalDeadBalance - initialDeadBalance,
            DEFAULT_EYE_BURN_AMOUNT,
            "Exact burn amount should be sent to dead address"
        );
    }

    function test_Security_CannotBypassEYEBurning() public {
        // Even with approval, insufficient balance prevents pause
        address newUser = address(0x6);
        vm.prank(owner);
        eyeToken.mint(newUser, DEFAULT_EYE_BURN_AMOUNT - 1); // 1 wei short

        vm.prank(newUser);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);

        vm.prank(newUser);
        vm.expectRevert();
        pauser.pause();

        assertFalse(b3.paused(), "Contract should not be paused without sufficient EYE");
    }

    // ============ EDGE CASE TESTS ============

    function test_EdgeCase_PauseWhenAlreadyPaused() public {
        // First pause
        vm.prank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        vm.prank(user1);
        pauser.pause();

        // Try to pause again
        vm.prank(user2);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        pauser.pause();
    }

    function test_EdgeCase_UnpauseWhenNotPaused() public {
        assertFalse(b3.paused(), "Should not be paused initially");

        // Try to unpause when not paused (should revert)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("ExpectedPause()"));
        pauser.unpause();
    }

    function test_EdgeCase_ConfigurableEYEBurnAmount() public {
        // Test with different burn amounts
        uint256 lowBurnAmount = 100 * 1e18;

        vm.prank(owner);
        pauser.config(lowBurnAmount, address(b3));

        vm.prank(user1);
        eyeToken.approve(address(pauser), lowBurnAmount);

        vm.prank(user1);
        pauser.pause();

        assertTrue(b3.paused(), "Should be paused with low burn amount");

        assertEq(
            eyeToken.balanceOf(address(0xdead)),
            lowBurnAmount,
            "Should burn only the configured amount"
        );
    }
}
