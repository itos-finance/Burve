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

    function compoundV3RangesExposed() public {
        compoundV3Ranges();
    }

    function getCompoundNominalLiqForCollectedAmountsExposed() public returns (uint128) {
        return getCompoundNominalLiqForCollectedAmounts();
    }

    function getCompoundAmountsPerUnitNominalLiqX64Exposed() public view returns (uint256, uint256) {
        return getCompoundAmountsPerUnitNominalLiqX64();
    }

    function collectV3FeesExposed() public {
        collectV3Fees();
    }
}
