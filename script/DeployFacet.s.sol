// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ValueFacet, ValueSingleFacet} from "../src/multi/facets/ValueFacet.sol";

import {Script} from "forge-std/Script.sol";

import {console2} from "forge-std/console2.sol";

contract DeployFacet is Script {
    /* Deployer */
    address deployerAddr;

    function run() public {
        deployerAddr = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address facet = address(new ValueFacet());
        console2.log("facet", facet);

        vm.stopBroadcast();
    }
}
