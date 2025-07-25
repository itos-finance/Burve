// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {BaseScript} from "../utils/BaseScript.sol";
import {Add_MEAD_RUSD_PYUSD} from "./Add_MEAD_RUSD_PYUSD.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract Call_MEAD_RUSD_PYUSD is BaseScript, Test {
    address constant OMNIPOOL = 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;

    function run() external {
        vm.startBroadcast(_getPrivateKey());

        Add_MEAD_RUSD_PYUSD executor = new Add_MEAD_RUSD_PYUSD(OMNIPOOL);

        console2.log("executor", address(executor));

        vm.stopBroadcast();
    }
}
