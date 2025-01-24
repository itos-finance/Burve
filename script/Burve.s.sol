// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BurveDeploymentLib} from "../src/deployment/BurveDeployLib.sol";
import {SimplexDiamond} from "../src/multi/Diamond.sol";

contract DeployBurveDiamond is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        (
            address liqFacet,
            address simplexFacet,
            address swapFacet
        ) = BurveDeploymentLib.deployFacets();
        SimplexDiamond diamond = new SimplexDiamond(
            liqFacet,
            simplexFacet,
            swapFacet
        );
        console2.log("Burve deployed at:", address(diamond));

        vm.stopBroadcast();
    }
}
