// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";

contract FetchSimplex is BaseScript {
    function run() external {
        address adjustor = simplexFacet.getAdjustor();
        console2.log("adjustor", adjustor);
    }
}
