// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Behodler3Tokenlaunch.sol";
import "../src/Pauser.sol";
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
        address eyeTokenAddr = vm.envAddress("EYE_TOKEN_ADDRESS");

        // Get Pauser configuration (optional - has defaults)
        uint256 eyeBurnAmount = vm.envOr("EYE_BURN_AMOUNT", uint256(1000 * 1e18)); // Default: 1000 EYE

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the TokenLaunch contract
        Behodler3Tokenlaunch tokenLaunch =
            new Behodler3Tokenlaunch(IERC20(inputTokenAddr), IBondingToken(bondingTokenAddr), IYieldStrategy(vaultAddr));

        console.log("Behodler3Tokenlaunch deployed to:", address(tokenLaunch));
        console.log("Owner:", tokenLaunch.owner());
        console.log("Input Token:", inputTokenAddr);
        console.log("Bonding Token:", bondingTokenAddr);
        console.log("Vault:", vaultAddr);

        // Deploy the Pauser contract
        Pauser pauser = new Pauser(eyeTokenAddr);
        console.log("\nPauser deployed to:", address(pauser));
        console.log("EYE Token:", eyeTokenAddr);

        // Configure Pauser with Behodler address and burn amount
        pauser.config(eyeBurnAmount, address(tokenLaunch));
        console.log("Pauser configured with burn amount:", eyeBurnAmount);

        // Set Pauser in Behodler contract
        tokenLaunch.setPauser(address(pauser));
        console.log("Pauser set in Behodler3Tokenlaunch");

        // Log important configuration
        console.log("\nDeployment Summary:");
        console.log("- Emergency pause enabled via Pauser contract");
        console.log("- Anyone can pause by burning", eyeBurnAmount / 1e18, "EYE tokens");
        console.log("- Only owner can unpause");
        console.log("- Pause blocks addLiquidity() and removeLiquidity()");

        vm.stopBroadcast();
    }
}
