// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {BaseScript} from "../utils/BaseScript.sol";

import {SimplexAdminFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {SimplexSetFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {SimplexGetFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {ValueSingleFacet} from "../../src/multi/facets/ValueFacet.sol";
import {AddTokenValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {RemoveTokenValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {QueryValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {ValueTokenFacet} from "../../src/multi/facets/ValueTokenFacet.sol";
import {LockFacet} from "../../src/multi/facets/LockFacet.sol";
import {VaultFacet} from "../../src/multi/facets/VaultFacet.sol";

contract DeploySimplexSetFacet is BaseScript {
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        SimplexSetFacet simplexSetFacet = new SimplexSetFacet();

        console2.log("SimplexSetFacet deployed at:", address(simplexSetFacet));

        vm.stopBroadcast();
    }
}
