// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {Test} from "forge-std/Test.sol";

import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {BaseScript} from "../utils/BaseScript.sol";
import {UpdateEdgeFees} from "./UpdateEdgeFees.sol";

/// Diamond: 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089
/// multisig: 0x9293f9FFC43F6fce06290285919541E963D87F51
contract Call_UpdateEdgeFees is BaseScript, Test {
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        UpdateEdgeFees updater = UpdateEdgeFees(address(0)); // fill in with the deployment script result

        updater.acceptOwnership();

        updater.updateAllEdgeFees();

        updater.transferOwnership();

        vm.stopBroadcast();
    }
}
