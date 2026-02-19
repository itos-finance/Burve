// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Condenser} from "../src/integrations/condenser/Condenser.sol";

contract DeployCondenser is Script {
    address constant BERACHAIN_ROUTER =
        0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;

    // Deployed address: 0x874Dfa2164933F802B0FfC7613CAB335Db7Ff788
    // Chain: Berachain (80094), Block: 17262816
    // Tx: 0x71f5e2dc5b060b18410773a4baddc41ecffa5ce1202e69df6315d1b49928ef99
    // Verified: https://berascan.com/address/0x874dfa2164933f802b0ffc7613cab335db7ff788

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Condenser condenser = new Condenser(BERACHAIN_ROUTER);
        console2.log("Condenser deployed at:", address(condenser));

        vm.stopBroadcast();
    }
}
