// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ClosureId, newClosureId} from "../Closure.sol";
import {Store} from "../Store.sol";
import {Edge} from "../Edge.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {Vertex, VertexId, newVertexId} from "../Vertex.sol";
import {VaultType} from "../VaultProxy.sol";
import {AdminLib} from "Commons/Util/Admin.sol";
import {TokenRegLib} from "../Token.sol";

struct SimplexStorage {
    string name;
    Edge defaultEdge;
}
contract SimplexFacet {
    event NewName(string newName);

    /// Convert your token of interest to the vertex id which you can
    /// sum with other vertex ids to create a closure Id.
    function getVertexId(address token) external view returns (uint16 vid) {
        return VertexId.unwrap(newVertexId(token));
    }

    /// Add a token into this simplex.
    function addVertex(address token, address vault, VaultType vType) external {
        AdminLib.validateOwner();
        Store.tokenRegistry().register(token);
        Store.vertex(newVertexId(token)).init(token, vault, vType);
        // TODO: event?
    }

    /// Get the number of currently installed vertices
    function numVertices() external view returns (uint8) {
        return TokenRegLib.numVertices();
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
        uint128 amplitude,
        int24 lowTick,
        int24 highTick,
        uint24 fee,
        uint8 feeProtocol
    ) external {
        AdminLib.validateOwner();
        Edge storage defaultE = Store.simplex().defaultEdge;
        defaultE.setRange(amplitude, lowTick, highTick);
        defaultE.setFee(fee, feeProtocol);
    }

    function setName(string calldata newName) external {
        AdminLib.validateOwner();
        Store.simplex().name = newName;
        emit NewName(newName);
    }

    function getName() external view returns (string memory name) {
        return Store.simplex().name;
    }
}
