// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {BaseScript} from "./BaseScript.sol";
import {SwapRouter, Route} from "../../src/integrations/router/SwapRouter.sol";

contract SwapRouterScript is BaseScript {
    Route[] routes;
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        routes = new Route[](9);

        routes[0] = Route({cid: 7, amountSpecified: 1733128114701});
        routes[1] = Route({cid: 13, amountSpecified: 4506483321});
        routes[2] = Route({cid: 15, amountSpecified: 4506483321});
        routes[3] = Route({cid: 29, amountSpecified: 4506483321});
        routes[4] = Route({cid: 31, amountSpecified: 4506483321});
        routes[5] = Route({cid: 45, amountSpecified: 4506483321});
        routes[6] = Route({cid: 47, amountSpecified: 4506483321});
        routes[7] = Route({cid: 61, amountSpecified: 4506483321});
        routes[8] = Route({cid: 63, amountSpecified: 999998235326502055});

        SwapRouter(0xF5c2C75eE2B03318C6F2E42957B35FF63986f6c6).swap(
            0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089,
            0xbe7dC5cC7977ac378ead410869D6c96f1E6C773e,
            0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce,
            0x549943e04f40284185054145c6E4e9568C1D3241,
            -969409,
            routes
        );

        vm.stopBroadcast();
    }
}
