// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {BaseScript} from "../utils/BaseScript.sol";
import {UpdateEdgeFees} from "./UpdateEdgeFees.sol";

contract Call_UpdateEdgeFees is BaseScript, Test {
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        UpdateEdgeFees executor = new UpdateEdgeFees();

        console2.log("executor", address(executor));

        vm.stopBroadcast();
    }
}
