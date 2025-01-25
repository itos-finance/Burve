// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {Edge} from "../Edge.sol";
import {MAX_TOKENS} from "../Token.sol";
import {Vertex, newVertexId} from "../Vertex.sol";
import {AdminLib} from "Commons/Util/Admin.sol";

struct SimplexStorage {
    uint256[MAX_TOKENS] protocolFees;
    Edge defaultEdge;
}
contract SimplexFacet {
    /// Add a token into this simplex.
    function addVertex(address token) external {
        AdminLib.validateOwner();
        // TODO

        // Init the vertex.
        Store.vertex(newVertexId(token)).init(token);
    }

    /// These will be the paramters used by all edges on construction.
    function setDefaultEdge(
        uint256 amplitude,
        int24 lowTick,
        int24 highTick,
        uint24 fee,
        uint8 feeProtocol
    ) external {
        AdminLib.validateOwner();
        Edge storage defaultE = Store.simplex().defaultEdge;
        defaultE.setRange(amplitude, lowTick, highTick);
        defaultE.setFees(fee, feeProtocol);
    }
}
