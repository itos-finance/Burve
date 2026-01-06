// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BeraAirdrop} from "../src/BeraAirdrop.sol";

contract DeployBeraAirdrop is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        BeraAirdrop airdrop = new BeraAirdrop();
        console2.log("BeraAirdrop deployed at:", address(airdrop));
        console2.log("Owner:", airdrop.owner());
        console2.log("Total recipients:", airdrop.recipientCount());

        vm.stopBroadcast();
    }
}
