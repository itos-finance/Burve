// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../../src/multi/Store.sol";
import {Simplex} from "../../src/multi/Simplex.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {Vertex} from "../../src/multi/vertex/Vertex.sol";
import {VertexId, VertexLib} from "../../src/multi/vertex/Id.sol";

contract StoreManipulatorFacet {
    function setProtocolEarnings(
        uint256[MAX_TOKENS] memory _protocolEarnings
    ) external {
        Store.simplex().protocolEarnings = _protocolEarnings;
    }

    function getVertex(VertexId vid) external view returns (Vertex memory v) {
        return Store.vertex(vid);
    }
}
