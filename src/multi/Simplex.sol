// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "./Store.sol";
import {Edge} from "./Edge.sol";

struct SimplexStorage {
    /// Add admin.
    /// The tick spacing used for all edges. Does not change.
    int24 tickSpacing;
}
contract SimplexFacet {
    /// Add a token into this simplex.
    function addVertex(address token) external {}

    /// These will be the paramters used by all edges on construction.
    function setDefaultEdge(
        uint256 amplitude,
        int24 lowTick,
        int24 highTick
    ) internal {}

    /// Set the parameters for a single edge.
    function setEdge(
        address token0,
        address token1,
        uint256 amplitude,
        int24 lowTick,
        int24 highTick
    ) internal {}
}
