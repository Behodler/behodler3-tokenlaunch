// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/mocks/MockBondingToken.sol";
import "@vault/mocks/MockERC20.sol";
import "@vault/mocks/MockVault.sol";

contract DebugState is Test {
    Behodler3Tokenlaunch public b3;
    MockBondingToken public bondingToken;
    MockERC20 public inputToken;
    MockVault public vault;
    address public owner = address(0x1);
    
    function setUp() public {
        vm.startPrank(owner);
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        bondingToken = new MockBondingToken("Bonding Token", "BOND");
        vault = new MockVault(owner);
        b3 = new Behodler3Tokenlaunch(inputToken, bondingToken, vault);
        vault.setClient(address(b3), true);
        b3.initializeVaultApproval();
        b3.setGoals(1_000_000 * 1e18, 0.9e18);
        vm.stopPrank();
    }
    
    function testDebugInitialState() public view {
        (uint256 vInput, uint256 vL, uint256 k) = b3.getVirtualPair();
        uint256 alpha = b3.alpha();
        uint256 beta = b3.beta();
        
        console.log("Virtual Input Tokens:", vInput);
        console.log("Virtual L:", vL);
        console.log("Virtual K:", k);
        console.log("Alpha:", alpha);
        console.log("Beta:", beta);
        console.log("BondingToken Total Supply:", bondingToken.totalSupply());
    }
}
