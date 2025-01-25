// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {Edge} from "../Edge.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {Vertex, newVertexId} from "../Vertex.sol";
import {AdminLib} from "Commons/Util/Admin.sol";

struct SimplexStorage {
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

    /// Withdraw fees earned by the protocol.
    function withdrawFees(address token, uint256 amount) external {
        AdminLib.validateOwner();
        // Normally tokens supporting the AMM ALWAYS resides in the vaults.
        // The only exception is
        // 1. When fees are earned by the protocol.
        // 2. When someone accidentally sends tokens to this address
        // 3. When someone donates.
        // Therefore we can just withdraw from this contract to resolve all three.
        TransferHelper.safeTransfer(token, msg.sender, amount);
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
