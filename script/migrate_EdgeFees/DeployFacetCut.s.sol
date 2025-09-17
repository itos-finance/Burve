// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {BaseAdminFacet} from "Commons/Util/Admin.sol";
import {BaseScript} from "../utils/BaseScript.sol";
import {FacetCut} from "./FacetCut.sol";

contract DeploySimplexSetFacet is BaseScript, Test {
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        FacetCut simplexSetFacet = new FacetCut();

        console2.log("FacetCut deployed at:", address(simplexSetFacet));

        vm.stopBroadcast();
    }
}
