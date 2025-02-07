// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {Edge} from "../Edge.sol";
import {AdminLib} from "Commons/Util/Admin.sol";
import {BurveFacetBase} from "./Base.sol";

contract EdgeFacet is BurveFacetBase {
    error InvalidTickRange();
    event EdgeFeeUpdated(address token0, address token1, uint24 fee);
    event EdgeRangeUpdated(
        address indexed token0,
        address indexed token1,
        uint128 amplitude,
        int24 lowTick,
        int24 highTick
    );

    /// Set the swap parameters for a single edge.
    function setEdge(
        address token0,
        address token1,
        uint128 amplitude,
        int24 lowTick,
        int24 highTick
    ) external validTokens(token0, token1) {
        AdminLib.validateOwner();
        if (lowTick >= highTick) revert InvalidTickRange();
        // We use the raw edge so we can preemptively set settings even if the vertices
        // aren't in use.
        Store.rawEdge(token0, token1).setRange(amplitude, lowTick, highTick);
        emit EdgeRangeUpdated(token0, token1, amplitude, lowTick, highTick);
    }

    function setEdgeFee(
        address token0,
        address token1,
        uint24 fee,
        uint8 feeProtocol
    ) external validTokens(token0, token1) {
        AdminLib.validateOwner();
        // We use the raw edge so we can preemptively set settings even if the vertices
        // aren't in use.
        Store.rawEdge(token0, token1).setFee(fee, feeProtocol);
        emit EdgeFeeUpdated(token0, token1, fee);
    }
}
