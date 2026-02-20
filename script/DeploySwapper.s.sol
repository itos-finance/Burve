// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Swapper} from "../src/integrations/swapper/Swapper.sol";

contract DeploySwapper is Script {
    address constant BERACHAIN_ROUTER =
        0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Swapper swapper = new Swapper(BERACHAIN_ROUTER);
        console2.log("Swapper deployed at:", address(swapper));

        vm.stopBroadcast();
    }
}
