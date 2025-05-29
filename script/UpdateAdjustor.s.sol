// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {SimplexSetFacet} from "../src/multi/facets/SimplexFacet.sol";
import {IAdjustor} from "../src/integrations/adjustor/IAdjustor.sol";
import {DecimalAdjustor} from "../src/integrations/adjustor/DecimalAdjustor.sol";

contract UpdateAdjustor is Script {
    /* Deployer */
    address deployerAddr;

    /* Diamond */
    address public diamond;
    SimplexSetFacet public simplexFacet;

    string public envFile = "script/bepolia-btc.json";

    function run() public {
        deployerAddr = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Read environment configuration
        string memory envJson = vm.readFile(envFile);
        diamond = vm.parseJsonAddress(envJson, ".diamond");

        vm.startBroadcast(deployerPrivateKey);

        // Get the simplex facet
        simplexFacet = SimplexSetFacet(diamond);

        // Deploy new decimal adjustor
        IAdjustor decimalAdj = new DecimalAdjustor();
        console2.log("New Decimal Adjustor deployed at:", address(decimalAdj));

        // Update the adjustor
        simplexFacet.setAdjustor(address(decimalAdj));
        console2.log("Adjustor updated to:", address(decimalAdj));

        vm.stopBroadcast();
    }
}
