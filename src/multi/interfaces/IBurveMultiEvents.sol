// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MAX_TOKENS} from "../Constants.sol";

interface IBurveMultiEvents {
    /// Emitted when overall simplex fees are changed..
    event SimplexFeesSet(uint128 defaultEdgeFeeX128, uint128 protocolTakeX128);
    /// Emitted when the edge fee is set.
    event EdgeFeeSet(uint8 indexed i, uint8 indexed j, uint128 edgeFeeX128);
    // Emitted whenever the balances change.
    event NewClosureBalances(
        uint16 cid,
        uint256 targetX128,
        uint256[MAX_TOKENS] balances
    );
}
