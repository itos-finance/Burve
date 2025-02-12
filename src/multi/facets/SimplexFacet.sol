// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {Edge} from "../Edge.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {Vertex, VertexId, newVertexId} from "../Vertex.sol";
import {VaultType} from "../VaultProxy.sol";
import {AdminLib} from "Commons/Util/Admin.sol";
import {TokenRegLib, TokenRegistry} from "../Token.sol";

struct SimplexStorage {
    string name;
    Edge defaultEdge;
}
contract SimplexFacet {
    event NewName(string newName);
    event VertexAdded(
        address indexed token,
        address indexed vault,
        VaultType vaultType
    );
    event FeesWithdrawn(address indexed token, uint256 amount);
    event DefaultEdgeSet(
        uint128 amplitude,
        int24 lowTick,
        int24 highTick,
        uint24 fee,
        uint8 feeProtocol
    );

    /* Getters */

    /// Convert your token of interest to the vertex id which you can
    /// sum with other vertex ids to create a closure Id.
    function getVertexId(address token) external view returns (uint16 vid) {
        return VertexId.unwrap(newVertexId(token));
    }

    /// Fetch the list of tokens registered in this simplex.
    function getTokens() external view returns (address[] memory tokens) {
        address[] storage _t = Store.tokenRegistry().tokens;
        tokens = new address[](_t.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i] = _t[i];
        }
    }

    /// Fetch the vertex index of the given token addresses.
    /// Returns a negative value if the token is not present.
    function getIndexes(
        address[] calldata tokens
    ) external view returns (int8[] memory idxs) {
        TokenRegistry storage reg = Store.tokenRegistry();
        idxs = new int8[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            idxs[i] = int8(reg.tokenIdx[tokens[i]]);
            if (idxs[i] == 0 && reg.tokens[0] != tokens[i]) {
                idxs[i] = -1;
            }
        }
    }

    /// Get the number of currently installed vertices
    function numVertices() external view returns (uint8) {
        return TokenRegLib.numVertices();
    }

    /* Admin Function */

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
        emit DefaultEdgeSet(amplitude, lowTick, highTick, fee, feeProtocol);
    }

    /// Add a token into this simplex.
    function addVertex(address token, address vault, VaultType vType) external {
        AdminLib.validateOwner();
        Store.tokenRegistry().register(token);
        Store.vertex(newVertexId(token)).init(token, vault, vType);
        emit VertexAdded(token, vault, vType);
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
        emit FeesWithdrawn(token, amount);
    }

    /* Naming */

    function setName(string calldata newName) external {
        AdminLib.validateOwner();
        Store.simplex().name = newName;
        emit NewName(newName);
    }

    function getName() external view returns (string memory name) {
        return Store.simplex().name;
    }
}
