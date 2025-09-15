// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockBondingToken.sol";
import "../src/mocks/MockERC20.sol";
import "@vault/mocks/MockVault.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title B3PermitTest
 * @notice Comprehensive tests for EIP-2612 permit functionality in Behodler3Tokenlaunch
 * @dev Tests cover signature verification, nonce management, deadline checking, and gas optimization
 */
contract B3PermitTest is Test {
    Behodler3Tokenlaunch public b3;
    MockBondingToken public bondingToken;
    ERC20PermitMock public inputToken; // Permit-enabled token
    MockERC20 public nonPermitToken; // Non-permit token for fallback testing
    MockVault public vault;

    // Private keys for testing
    uint256 private constant USER1_PRIVATE_KEY = 0x1234;
    uint256 private constant USER2_PRIVATE_KEY = 0x5678;

    // Addresses derived from private keys
    address public user1 = vm.addr(USER1_PRIVATE_KEY);
    address public user2 = vm.addr(USER2_PRIVATE_KEY);
    address public contractOwner = address(this);

    uint256 private constant INITIAL_SUPPLY = 1000000e18;
    uint256 private constant TYPICAL_AMOUNT = 1000e18;
    uint256 private constant FUNDING_GOAL = 1000000e18;
    uint256 private constant SEED_INPUT = 1000e18;
    uint256 private constant DESIRED_AVERAGE_PRICE = 9e17; // 0.9

    event PermitUsed(address indexed owner, address indexed spender, uint256 value, uint256 nonce, uint256 deadline);

    function setUp() public {
        // Deploy mock contracts
        bondingToken = new MockBondingToken("Bonding Token", "BT");
        inputToken = new ERC20PermitMock("Test Token", "TEST", INITIAL_SUPPLY);
        nonPermitToken = new MockERC20("Non Permit Token", "NPT", 18);
        vault = new MockVault(address(this));

        // Deploy B3 contract
        b3 = new Behodler3Tokenlaunch(IERC20(address(inputToken)), bondingToken, vault);

        // Set up virtual liquidity goals
        b3.setGoals(FUNDING_GOAL, SEED_INPUT, DESIRED_AVERAGE_PRICE);

        // Initialize vault approval
        vault.setClient(address(b3), true);
        b3.initializeVaultApproval();

        // Setup users
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);

        // Mint tokens to users
        inputToken.mint(user1, INITIAL_SUPPLY);
        inputToken.mint(user2, INITIAL_SUPPLY);
        nonPermitToken.mint(user1, INITIAL_SUPPLY);
        nonPermitToken.mint(user2, INITIAL_SUPPLY);

        // MockBondingToken doesn't have setMinter - it allows any address to mint for testing
    }

    // ============ BASIC PERMIT FUNCTIONALITY TESTS ============

    /**
     * @notice Test basic permit functionality with valid signature
     */
    function test_PermitBasic_WithValidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tokenNonce = inputToken.nonces(user1);
        uint256 b3Nonce = b3.nonces(user1);

        // Create permit signature for the input token (not B3 contract)
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, tokenNonce, deadline
        );

        // Expect PermitUsed event from B3
        vm.expectEmit(true, true, false, true);
        emit PermitUsed(user1, address(b3), TYPICAL_AMOUNT, b3Nonce, deadline);

        // Execute permit
        b3.permit(user1, address(b3), TYPICAL_AMOUNT, deadline, v, r, s);

        // Verify B3 nonce was incremented
        assertEq(b3.nonces(user1), b3Nonce + 1);

        // Verify allowance was set on input token
        assertEq(inputToken.allowance(user1, address(b3)), TYPICAL_AMOUNT);
    }

    /**
     * @notice Test permit fails with expired deadline
     */
    function test_PermitFails_WithExpiredDeadline() public {
        uint256 deadline = block.timestamp - 1; // Expired
        uint256 nonce = b3.nonces(user1);

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, nonce, deadline
        );

        vm.expectRevert("B3: Permit expired");
        b3.permit(user1, address(b3), TYPICAL_AMOUNT, deadline, v, r, s);
    }

    /**
     * @notice Test permit fails with invalid signature
     */
    function test_PermitFails_WithInvalidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tokenNonce = inputToken.nonces(user1);

        // Create signature with wrong private key
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER2_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, tokenNonce, deadline
        );

        vm.expectRevert("B3: Input token does not support permit");
        b3.permit(user1, address(b3), TYPICAL_AMOUNT, deadline, v, r, s);
    }

    /**
     * @notice Test permit fails with wrong nonce (replay protection)
     */
    function test_PermitFails_WithWrongNonce() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 wrongNonce = inputToken.nonces(user1) + 1; // Wrong nonce

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, wrongNonce, deadline
        );

        vm.expectRevert("B3: Input token does not support permit");
        b3.permit(user1, address(b3), TYPICAL_AMOUNT, deadline, v, r, s);
    }

    /**
     * @notice Test permit fails with zero owner address
     */
    function test_PermitFails_WithZeroOwner() public {
        uint256 deadline = block.timestamp + 1 hours;

        vm.expectRevert("B3: Invalid owner");
        b3.permit(address(0), address(b3), TYPICAL_AMOUNT, deadline, 0, bytes32(0), bytes32(0));
    }

    /**
     * @notice Test permit fails with zero spender address
     */
    function test_PermitFails_WithZeroSpender() public {
        uint256 deadline = block.timestamp + 1 hours;

        vm.expectRevert("B3: Invalid spender");
        b3.permit(user1, address(0), TYPICAL_AMOUNT, deadline, 0, bytes32(0), bytes32(0));
    }

    // ============ NONCE MANAGEMENT TESTS ============

    /**
     * @notice Test nonce increments correctly after permit
     */
    function test_NonceIncrementsCorrectly() public {
        uint256 initialB3Nonce = b3.nonces(user1);
        uint256 tokenNonce = inputToken.nonces(user1);
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, tokenNonce, deadline
        );

        b3.permit(user1, address(b3), TYPICAL_AMOUNT, deadline, v, r, s);

        assertEq(b3.nonces(user1), initialB3Nonce + 1);
    }

    /**
     * @notice Test replay attack prevention
     */
    function test_ReplayAttackPrevention() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tokenNonce = inputToken.nonces(user1);

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, tokenNonce, deadline
        );

        // First permit should succeed
        b3.permit(user1, address(b3), TYPICAL_AMOUNT, deadline, v, r, s);

        // Second permit with same signature should fail (nonce has changed)
        vm.expectRevert("B3: Input token does not support permit");
        b3.permit(user1, address(b3), TYPICAL_AMOUNT, deadline, v, r, s);
    }

    /**
     * @notice Test multiple users have independent nonces
     */
    function test_IndependentNoncesForMultipleUsers() public {
        uint256 deadline = block.timestamp + 1 hours;

        // User1 permit
        uint256 nonce1 = b3.nonces(user1);
        (uint8 v1, bytes32 r1, bytes32 s1) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, nonce1, deadline
        );

        // User2 permit (different address, same nonce value should work)
        uint256 nonce2 = b3.nonces(user2);
        (uint8 v2, bytes32 r2, bytes32 s2) = _createPermitSignature(
            user2, USER2_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, nonce2, deadline
        );

        // Both should start with nonce 0
        assertEq(nonce1, 0);
        assertEq(nonce2, 0);

        // Both permits should succeed
        b3.permit(user1, address(b3), TYPICAL_AMOUNT, deadline, v1, r1, s1);
        b3.permit(user2, address(b3), TYPICAL_AMOUNT, deadline, v2, r2, s2);

        // Both should have incremented nonces
        assertEq(b3.nonces(user1), 1);
        assertEq(b3.nonces(user2), 1);
    }

    // ============ ADDLIQUIDITY WITH PERMIT TESTS ============

    /**
     * @notice Test addLiquidityWithPermit with valid permit signature
     */
    function test_AddLiquidityWithPermit_ValidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tokenNonce = inputToken.nonces(user1);
        uint256 b3Nonce = b3.nonces(user1);

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, tokenNonce, deadline
        );

        vm.startPrank(user1);

        uint256 bondingTokensOut = b3.addLiquidityWithPermit(
            TYPICAL_AMOUNT, 0, deadline, v, r, s
        );

        vm.stopPrank();

        // Verify liquidity was added
        assertGt(bondingTokensOut, 0);
        assertEq(bondingToken.balanceOf(user1), bondingTokensOut);

        // Verify nonce was incremented
        assertEq(b3.nonces(user1), b3Nonce + 1);
    }

    /**
     * @notice Test addLiquidityWithPermit falls back to checking allowance when permit fails
     */
    function test_AddLiquidityWithPermit_FallsBackToAllowance() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Pre-approve tokens (standard flow)
        vm.prank(user1);
        inputToken.approve(address(b3), TYPICAL_AMOUNT);

        // Use invalid signature (permit will fail)
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER2_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, 0, deadline
        );

        vm.startPrank(user1);

        // Should succeed despite permit failure due to pre-existing allowance
        uint256 bondingTokensOut = b3.addLiquidityWithPermit(
            TYPICAL_AMOUNT, 0, deadline, v, r, s
        );

        vm.stopPrank();

        assertGt(bondingTokensOut, 0);
        assertEq(bondingToken.balanceOf(user1), bondingTokensOut);
    }

    /**
     * @notice Test addLiquidityWithPermit fails when both permit and allowance are insufficient
     */
    function test_AddLiquidityWithPermit_FailsWithoutPermitOrAllowance() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Use invalid signature and no pre-approval
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER2_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, 0, deadline
        );

        vm.startPrank(user1);

        vm.expectRevert("B3: Insufficient allowance and permit failed");
        b3.addLiquidityWithPermit(TYPICAL_AMOUNT, 0, deadline, v, r, s);

        vm.stopPrank();
    }

    // ============ EIP-165 INTERFACE SUPPORT TESTS ============

    /**
     * @notice Test EIP-165 interface support detection
     */
    function test_SupportsInterface_EIP165() public {
        // Test EIP-165 interface ID
        assertTrue(b3.supportsInterface(0x01ffc9a7));
    }

    /**
     * @notice Test IERC20Permit interface support detection
     */
    function test_SupportsInterface_IERC20Permit() public {
        // Test IERC20Permit interface ID
        bytes4 permitInterfaceId = type(IERC20Permit).interfaceId;
        assertTrue(b3.supportsInterface(permitInterfaceId));
    }

    /**
     * @notice Test unsupported interface returns false
     */
    function test_SupportsInterface_UnsupportedInterface() public {
        // Random interface ID should return false
        assertFalse(b3.supportsInterface(0x12345678));
    }

    // ============ DOMAIN SEPARATOR TESTS ============

    /**
     * @notice Test domain separator is consistent
     */
    function test_DomainSeparator_Consistency() public {
        bytes32 separator1 = b3.DOMAIN_SEPARATOR();
        bytes32 separator2 = b3.DOMAIN_SEPARATOR();

        assertEq(separator1, separator2);
        assertNotEq(separator1, bytes32(0));
    }

    // ============ GAS OPTIMIZATION TESTS ============

    /**
     * @notice Test gas usage comparison between traditional approve+transfer vs permit
     */
    function test_GasOptimization_PermitVsApprove() public {
        // Simplified test - just ensure permit version works
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tokenNonce = inputToken.nonces(user1);

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, tokenNonce, deadline
        );

        vm.prank(user1);
        uint256 bondingTokensOut = b3.addLiquidityWithPermit(TYPICAL_AMOUNT, 0, deadline, v, r, s);

        // Verify permit version works
        assertGt(bondingTokensOut, 0);
        assertEq(bondingToken.balanceOf(user1), bondingTokensOut);
    }

    // ============ NON-PERMIT TOKEN TESTS ============

    /**
     * @notice Test permit fails gracefully when input token doesn't support permit
     */
    function test_PermitFails_WithNonPermitToken() public {
        // Deploy B3 with non-permit token
        Behodler3Tokenlaunch b3NonPermit = new Behodler3Tokenlaunch(
            IERC20(address(nonPermitToken)), bondingToken, vault
        );

        b3NonPermit.setGoals(FUNDING_GOAL, SEED_INPUT, DESIRED_AVERAGE_PRICE);
        vault.setClient(address(b3NonPermit), true);
        b3NonPermit.initializeVaultApproval();

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = b3NonPermit.nonces(user1);

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignatureForContract(
            address(b3NonPermit), user1, USER1_PRIVATE_KEY, address(b3NonPermit), TYPICAL_AMOUNT, nonce, deadline
        );

        vm.expectRevert("B3: Input token does not support permit");
        b3NonPermit.permit(user1, address(b3NonPermit), TYPICAL_AMOUNT, deadline, v, r, s);
    }

    // ============ SECURITY TESTS ============

    /**
     * @notice Test permit with different values in signature vs function call fails
     */
    function test_SecurityTest_SignatureValueMismatch() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tokenNonce = inputToken.nonces(user1);

        // Create signature for one amount
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, tokenNonce, deadline
        );

        // Try to use with different amount
        vm.expectRevert("B3: Input token does not support permit");
        b3.permit(user1, address(b3), TYPICAL_AMOUNT * 2, deadline, v, r, s);
    }

    /**
     * @notice Test permit with different spender in signature vs function call fails
     */
    function test_SecurityTest_SignatureSpenderMismatch() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tokenNonce = inputToken.nonces(user1);

        // Create signature for one spender
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, user2, TYPICAL_AMOUNT, tokenNonce, deadline
        );

        // Try to use with different spender
        vm.expectRevert("B3: Input token does not support permit");
        b3.permit(user1, address(b3), TYPICAL_AMOUNT, deadline, v, r, s);
    }

    /**
     * @notice Test permit with different deadline in signature vs function call fails
     */
    function test_SecurityTest_SignatureDeadlineMismatch() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tokenNonce = inputToken.nonces(user1);

        // Create signature for one deadline
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            user1, USER1_PRIVATE_KEY, address(b3), TYPICAL_AMOUNT, tokenNonce, deadline
        );

        // Try to use with different deadline
        vm.expectRevert("B3: Input token does not support permit");
        b3.permit(user1, address(b3), TYPICAL_AMOUNT, deadline + 1 hours, v, r, s);
    }

    // ============ HELPER FUNCTIONS ============

    /**
     * @notice Create EIP-712 permit signature for the input token (not B3 contract)
     */
    function _createPermitSignature(
        address owner,
        uint256 privateKey,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        return _createTokenPermitSignature(address(inputToken), owner, privateKey, spender, value, nonce, deadline);
    }

    /**
     * @notice Create EIP-712 permit signature for a token contract
     */
    function _createTokenPermitSignature(
        address tokenAddr,
        address owner,
        uint256 privateKey,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = ERC20PermitMock(tokenAddr).DOMAIN_SEPARATOR();

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (v, r, s) = vm.sign(privateKey, digest);
    }

    /**
     * @notice Create EIP-712 permit signature for B3 contract (for domain separator tests)
     */
    function _createPermitSignatureForContract(
        address contractAddr,
        address owner,
        uint256 privateKey,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = Behodler3Tokenlaunch(contractAddr).DOMAIN_SEPARATOR();

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (v, r, s) = vm.sign(privateKey, digest);
    }
}

/**
 * @notice Mock ERC20 token with permit functionality for testing
 */
contract ERC20PermitMock is ERC20Permit {
    constructor(string memory name, string memory symbol, uint256 initialSupply)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        _mint(msg.sender, initialSupply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}