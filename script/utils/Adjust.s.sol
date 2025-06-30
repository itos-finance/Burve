// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {BaseScript} from "./BaseScript.sol";
import {IAdjustor} from "../../src/integrations/adjustor/IAdjustor.sol";

contract Adjust is BaseScript {
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        uint256 normalized = IAdjustor(
            0x2EFe5fFa9884E9eF76883dF8212b5d70927b8586
        ).toNominal(
                0x549943e04f40284185054145c6E4e9568C1D3241,
                uint256(200000),
                false
            );
        console2.log(normalized);

        address adjustor = simplexFacet.getAdjustor();
        console2.log(adjustor);

        vm.stopBroadcast();
    }
}
