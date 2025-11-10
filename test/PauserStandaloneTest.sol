// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Pauser.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockBondingToken.sol";
import "@vault/mocks/MockERC20.sol";
import "@vault/concreteYieldStrategies/AutoDolaYieldStrategy.sol";
import "@vault/mocks/MockAutoDOLA.sol";
import "@vault/mocks/MockMainRewarder.sol";

/**
 * @title PauserStandaloneTest
 * @notice Standalone test to verify pause functionality works correctly
 * @dev Minimal test to verify core functionality without depending on broken existing tests
 */
contract PauserStandaloneTest is Test {
    Behodler3Tokenlaunch public b3;
    Pauser public pauser;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;
    MockERC20 public eyeToken;
    AutoDolaYieldStrategy public vault;

    address public owner = address(0x1);
    address public user1 = address(0x2);

    uint256 constant FUNDING_GOAL = 1_000_000 * 1e18;
    uint256 constant DESIRED_AVG_PRICE = 0.9e18;
    uint256 constant DEFAULT_EYE_BURN_AMOUNT = 1000 * 1e18;
    uint256 constant INITIAL_EYE_BALANCE = 10_000 * 1e18;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy contracts
        bondingToken = new MockBondingToken("BondingToken", "BOND");
        inputToken = new MockERC20("TestToken", "TEST", 18);
        eyeToken = new MockERC20("EYE", "EYE", 18);

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

        // Deploy B3
        b3 = new Behodler3Tokenlaunch(inputToken, bondingToken, vault);

        // Setup vault
        vault.setClient(address(b3), true);
        b3.initializeVaultApproval();
        b3.setGoals(FUNDING_GOAL, DESIRED_AVG_PRICE);

        // Deploy and configure Pauser
        pauser = new Pauser(address(eyeToken));
        pauser.config(DEFAULT_EYE_BURN_AMOUNT, address(b3));
        b3.setPauser(address(pauser));

        // Setup test users
        eyeToken.mint(user1, INITIAL_EYE_BALANCE);

        vm.stopPrank();
    }

    function test_CoreFunctionality() public {
        // 1. Verify initial state
        assertFalse(b3.paused(), "Should not be paused initially");
        assertEq(b3.pauser(), address(pauser), "Pauser should be set");
        assertEq(pauser.eyeBurnAmount(), DEFAULT_EYE_BURN_AMOUNT, "Burn amount should be set");

        // 2. User1 triggers pause
        vm.startPrank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        pauser.pause();
        vm.stopPrank();

        // 3. Verify paused
        assertTrue(b3.paused(), "Should be paused");
        assertEq(eyeToken.balanceOf(address(0xdead)), DEFAULT_EYE_BURN_AMOUNT, "EYE should be burned");

        // 4. Owner unpauses
        vm.prank(owner);
        pauser.unpause();

        // 5. Verify unpaused
        assertFalse(b3.paused(), "Should be unpaused");
    }

    function test_PauseBlocksOperations() public {
        // Setup liquidity
        vm.startPrank(owner);
        inputToken.mint(user1, 10_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(user1);
        inputToken.approve(address(b3), 10_000 * 1e18);

        // Add liquidity before pause (should work)
        uint256 bondingTokens = b3.addLiquidity(1000 * 1e18, 0);
        assertTrue(bondingTokens > 0, "Should receive bonding tokens");

        // Pause
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        pauser.pause();

        // Try to add liquidity (should fail)
        vm.expectRevert();
        b3.addLiquidity(1000 * 1e18, 0);

        // Try to remove liquidity (should fail)
        vm.expectRevert();
        b3.removeLiquidity(bondingTokens, 0);

        vm.stopPrank();

        // Unpause
        vm.prank(owner);
        pauser.unpause();

        // Operations should work again
        vm.prank(user1);
        uint256 inputTokensOut = b3.removeLiquidity(bondingTokens / 2, 0);
        assertTrue(inputTokensOut > 0, "Should receive input tokens after unpause");
    }

    function test_SecurityChecks() public {
        // Non-pauser cannot pause B3 directly
        vm.prank(user1);
        vm.expectRevert();
        b3.pause();

        // Pause via Pauser
        vm.startPrank(user1);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        pauser.pause();
        vm.stopPrank();

        // Non-owner cannot unpause via Pauser
        vm.prank(user1);
        vm.expectRevert();
        pauser.unpause();

        // Non-owner cannot unpause B3 directly
        vm.prank(user1);
        vm.expectRevert();
        b3.unpause();

        // Owner can unpause
        vm.prank(owner);
        pauser.unpause();

        assertFalse(b3.paused(), "Should be unpaused");
    }

    function test_EYEBurningRequired() public {
        // User without EYE approval cannot pause
        address poorUser = address(0x5);
        vm.prank(owner);
        eyeToken.mint(poorUser, DEFAULT_EYE_BURN_AMOUNT);

        // No approval
        vm.prank(poorUser);
        vm.expectRevert();
        pauser.pause();

        // With approval, should work
        vm.startPrank(poorUser);
        eyeToken.approve(address(pauser), DEFAULT_EYE_BURN_AMOUNT);
        pauser.pause();
        vm.stopPrank();

        assertTrue(b3.paused(), "Should be paused");
        assertEq(
            eyeToken.balanceOf(address(0xdead)),
            DEFAULT_EYE_BURN_AMOUNT,
            "EYE should be burned"
        );
    }
}
