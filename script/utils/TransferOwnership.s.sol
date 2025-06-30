// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";

contract TransferOwnershipScript is BaseScript {
    address multisig;

    function run() external {
        // vm.startBroadcast(_getPrivateKey());

        // BaseAdminFacet(diamondAddr).transferOwnership(
        //     address(0x9293f9FFC43F6fce06290285919541E963D87F51)
        // );

        // vm.stopBroadcast();

        // vm.startPrank(address(0x9293f9FFC43F6fce06290285919541E963D87F51));

        // BaseAdminFacet(diamondAddr).acceptOwnership();
        address newOwner = BaseAdminFacet(diamondAddr).owner();
        console2.log("diamondAddr", diamondAddr);
        console2.log("owner", newOwner);

        // vm.stopPrank();
    }
}
