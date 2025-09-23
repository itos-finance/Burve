// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {Test} from "forge-std/Test.sol";

import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {BaseScript} from "../utils/BaseScript.sol";
import {FacetCut} from "./FacetCut.sol";

contract Execute_FacetCut is BaseScript, Test {
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        FacetCut cut = FacetCut(address(0)); // fill in with the deployment script result

        cut.acceptOwnership();

        cut.performFacetCut();

        cut.transferOwnership();

        vm.stopBroadcast();
    }
}
