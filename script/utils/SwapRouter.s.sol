// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {BaseScript} from "./BaseScript.sol";
import {SwapRouter, Route} from "../../src/integrations/router/SwapRouter.sol";

contract Adjust is BaseScript {
    Route[] routes;
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        routes = new Route[](2);

        routes[0] = Route({cid: 3, amountSpecified: 199919});
        routes[1] = Route({cid: 7, amountSpecified: 0});

        SwapRouter(0xF5c2C75eE2B03318C6F2E42957B35FF63986f6c6).swap(
            0x89c3208A2312EEC4ad620bD78b719198Bbd0f2c7,
            0xbe7dC5cC7977ac378ead410869D6c96f1E6C773e,
            0x549943e04f40284185054145c6E4e9568C1D3241,
            0x779Ded0c9e1022225f8E0630b35a9b54bE713736,
            -39977,
            routes
        );

        vm.stopBroadcast();
    }
}
