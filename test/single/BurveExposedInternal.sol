// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Burve} from "../../src/single/Burve.sol";
import {TickRange} from "../../src/single/TickRange.sol";

contract BurveExposedInternal is Burve {
    constructor(
        address _pool,
        address _island,
        address _stationProxy,
        TickRange[] memory _ranges,
        uint128[] memory _weights
    ) Burve(_pool, _island, _stationProxy, _ranges, _weights) {}

    function getMintAmountsPerUnitNominalLiqX64Exposed(
        bool skipIsland
    ) public view returns (uint256, uint256) {
        return getMintAmountsPerUnitNominalLiqX64(skipIsland);
    }

    function collectV3FeesExposed() public {
        collectV3Fees();
    }
}
