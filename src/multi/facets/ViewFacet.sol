// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {Edge, EdgeImpl} from "../Edge.sol";
import {Vertex, VertexId, newVertexId} from "../Vertex.sol";
import {AssetStorage} from "../Asset.sol";
import {VaultStorage} from "../VaultProxy.sol";
import {SimplexStorage} from "./SimplexFacet.sol";
import {ClosureId, newClosureId} from "../Closure.sol";

/// @notice Mock facet that exposes storage access functions for testing
contract ViewFacet {
    function getClosureId(
        address[] memory tokens
    ) external view returns (ClosureId) {
        return newClosureId(tokens);
    }

    function getEdge(
        address token0,
        address token1
    ) external view returns (Edge memory) {
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
        return Store.edge(token0, token1);
    }

    function getPriceX128(
        address token0,
        address token1,
        uint128 balance0,
        uint128 balance1
    ) external view returns (uint256 priceX128) {
        Edge storage self = Store.edge(token0, token1);
        return self.getPriceX128(balance0, balance1);
    }

    function getVertex(
        address token
    )
        external
        view
        returns (
            VertexId vid,
            ClosureId[] memory homs,
            bool[] memory homSetFlags
        )
    {
        Vertex storage v = Store.vertex(newVertexId(token));
        vid = v.vid;

        // We'll return the first connected vertex's homs and homSet for testing
        // You can add more comprehensive vertex data access as needed
        VertexId firstNeighbor = VertexId.wrap(1); // First possible vertex
        homs = v.homs[firstNeighbor];
        homSetFlags = new bool[](homs.length);
        for (uint i = 0; i < homs.length; i++) {
            homSetFlags[i] = v.homSet[firstNeighbor][homs[i]];
        }
    }

    function getAssetShares(
        address owner,
        ClosureId cid
    ) external view returns (uint256 shares, uint256 totalShares) {
        AssetStorage storage assets = Store.assets();
        shares = assets.shares[owner][cid];
        totalShares = assets.totalShares[cid];
    }

    function getDefaultEdge() external view returns (Edge memory) {
        return Store.simplex().defaultEdge;
    }
}
