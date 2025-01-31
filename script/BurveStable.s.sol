// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Burve, TickRange} from "../src/Burve.sol";

contract DeployBurveStable is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address pool = 0x246c12D7F176B93e32015015dAB8329977de981B;
        address island = 0x63b0EdC427664D4330F72eEc890A86b3F98ce225;

        TickRange[] memory ranges = new TickRange[](2);
        ranges[0] = TickRange(0, 0);
        ranges[1] = TickRange(-1000, 1000);

        uint128[] memory weights = new uint128[](2);
        weights[0] = 2;
        weights[1] = 1;

        Burve burve = new Burve(pool, island, ranges, weights);

        console2.log("Burve deployed at:", address(burve));

        vm.stopBroadcast();
    }
}
