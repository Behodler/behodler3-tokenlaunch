// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IBondingToken.sol";
import "@vault/interfaces/IYieldStrategy.sol";

/**
 * @title Deploy
 * @notice Deployment script for Behodler3Tokenlaunch contract
 * @dev This script deploys the simplified TokenLaunch contract without EIP-2612 permit functionality
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get deployment parameters from environment
        address inputTokenAddr = vm.envAddress("INPUT_TOKEN_ADDRESS");
        address bondingTokenAddr = vm.envAddress("BONDING_TOKEN_ADDRESS");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the TokenLaunch contract
        Behodler3Tokenlaunch tokenLaunch =
            new Behodler3Tokenlaunch(IERC20(inputTokenAddr), IBondingToken(bondingTokenAddr), IYieldStrategy(vaultAddr));

        console.log("Behodler3Tokenlaunch deployed to:", address(tokenLaunch));
        console.log("Owner:", tokenLaunch.owner());
        console.log("Input Token:", inputTokenAddr);
        console.log("Bonding Token:", bondingTokenAddr);
        console.log("Vault:", vaultAddr);

        // Log important configuration
        console.log("Contract deployed successfully without permit functionality");
        console.log("Uses standard ERC20 approve/transfer pattern");

        vm.stopBroadcast();
    }
}
