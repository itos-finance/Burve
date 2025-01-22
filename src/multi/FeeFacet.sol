// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "./Store.sol";

/*
 * A simple facet for managing the fee rate for each edge (pool) in the Burve setup. Fees in burve are
 * dynamic unlike UniswapV3 where the fees are set at the time of pool deployment.
 */
library FeeFacet {
    /// @notice emitted when an Admin updates the edge's fee rate for swaps
    event UpdateEdgeFee(address token0, address token1, uint24 fee);

    /**
     * @notice Admin level function to set the dynmaic fee in bps for a
     * @param token0 related to the pool being set
     * @param token1 related to the pool being set
     * @param fee to set on an edge in bps
     */
    function setDynamicFee(
        address token0,
        address token1,
        uint24 fee
    ) external {
        Store.edge(token0, token1).fee = fee;

        emit UpdateEdgeFee(token0, token1, fee);
    }

    /**
     * @notice fetches the fee for an edge specified by the token pair
     * @param token0 in the edge
     * @param token1 in the edge
     * @return fee rate
     */
    function getDynamicFee(
        address token0,
        address token1
    ) internal returns (uint24 fee) {
        return Store.edge(token0, token1).fee;
    }
}
