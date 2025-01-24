// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {AssetStorage} from "./Asset.sol";
import {VaultStorage} from "./VaultProxy.sol";
import {Vertex, VertexId} from "./Vertex.sol";
import {TokenRegistry} from "./Token.sol";
import {Edge} from "./Edge.sol";
import {SimplexStorage} from "./facets/SimplexFacet.sol";

struct Storage {
    AssetStorage assets;
    TokenRegistry tokenReg;
    VaultStorage _vaults;
    SimplexStorage simplex;
    // Graph elements
    mapping(VertexId => Vertex) vertices;
    mapping(address => mapping(address => Edge)) edges; // Mapping from token,token to uniswap pool.
}

library Store {
    bytes32 public constant MULTI_STORAGE_POSITION =
        keccak256("multi.diamond.storage.20250113");

    function load() internal view returns (Storage storage s) {
        bytes32 position = MULTI_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    function vertex(VertexId vid) internal view returns (Vertex storage v) {
        return load().vertices[vid];
    }

    function tokenRegistry()
        internal
        view
        returns (TokenRegistry storage tokenReg)
    {
        return load().tokenReg;
    }

    function edge(
        address token0,
        address token1
    ) internal view returns (Edge storage _edge) {
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
        return load().edges[token0][token1];
    }

    function vaults() internal view returns (VaultStorage storage v) {
        return load()._vaults;
    }

    function assets() internal view returns (AssetStorage storage a) {
        return load().assets;
    }

    function simplex() internal view returns (SimplexStorage storage s) {
        return load().simplex;
    }
}
