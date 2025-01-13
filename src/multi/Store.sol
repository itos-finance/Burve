// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {VaultE4626} from "./vertex/E4626.sol";
import {Vertex, VertexId, SubVertexId, SubVertex} from "./Vertex.sol";
import {TokenRegistry} from "./Token.sol";
import {HomSet} from "./HomSet.sol";

struct Storage {
    TokenRegistry tokenReg;
    // Graph elements
    mapping(VertexId => Vertex) vertices;
    mapping(address => mapping(address => HomSet)) homSets; // Mapping from token,token to uniswap pool.
    // Vaults
    mapping(address => VaultE4626) e4626s;
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

    function subVertex(
        SubVertexId svid
    ) internal view returns (SubVertex storage sv) {
        return load().subVertices[svid];
    }

    function E4626s(
        address vault
    ) internal view returns (VaultE4626 storage vaultProxy) {
        return load().e4626s[vault];
    }

    function tokenRegistry()
        internal
        view
        returns (TokenRegistry storage tokenReg)
    {
        return load().tokenReg;
    }

    function homSet(
        address token0,
        address token1
    ) internal view returns (HomSet storage _homSet) {
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
        return load().homSets[token0][token1];
    }
}
