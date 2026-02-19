// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Condenser} from "../src/integrations/condenser/Condenser.sol";

contract DeployCondenser is Script {
    address constant BERACHAIN_ROUTER =
        0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Condenser condenser = new Condenser(BERACHAIN_ROUTER);
        console2.log("Condenser deployed at:", address(condenser));

        vm.stopBroadcast();
    }
}
