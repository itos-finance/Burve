// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {Test} from "forge-std/Test.sol";

import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {BaseScript} from "../utils/BaseScript.sol";
import {Add_MEAD_RUSD_PYUSD} from "./Add_MEAD_RUSD_PYUSD.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// USD pool 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089
/// multisig 0x9293f9FFC43F6fce06290285919541E963D87F51
contract Call_MEAD_RUSD_PYUSD is BaseScript, Test {
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        Add_MEAD_RUSD_PYUSD executor = Add_MEAD_RUSD_PYUSD(
            address(0xeA5A3388D0254C9B684AB074674661493774BA0E)
        ); // fill in with the deployment script result

        executor.acceptOwnership();

        executor.deployMEAD();

        executor.deployRUSD();

        executor.deployPYUSD();

        uint16 minClosure = 1 << 6;
        uint16 maxClosure = 1 << 9;
        uint16 offset = 4;
        for (uint16 min = minClosure; min < maxClosure; min += offset) {
            executor.initializeClosure(
                min,
                min + offset > maxClosure ? maxClosure : min + offset
            );
        }

        executor.transferOwnership();

        vm.stopBroadcast();
    }
}
