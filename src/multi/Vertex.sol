// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TokenRegLib, MAX_TOKENS} from "./Token.sol";
import {VaultProxyLib, VaultType} from "./VaultProxy.sol";

type VertexId is uint16;
function newVertexId(uint8 idx) returns (VertexId) {
    // We sanitize the idx beforehand for efficiency reasons.
    return VertexId.wrap(1 << idx);
}
function newVertexId(address token) returns (VertexId) {
    return newVertexId(TokenRegLib.getIdx(token));
}

/**
 * Vertices supply tokens to the trading pools. These track how the tokens they hold are split across subvertices.
 * The subvertices track how their tokens are split across closures.
 */
struct Vertex {
    VertexId vid;
    mapping(VertexId => ClosureId[]) homs;
    mapping(VertexId => mapping(ClosureId => bool)) homSet;
}

using VertexImpl for Vertex global;

/* A vertex encapsulates the information of a single token */
library VertexImpl {
    /// Thrown when we try to subtract an amount too large for the edge in question.
    error InsufficientWithdraw(
        VertexId source,
        VertexId other,
        uint256 total, // The total balance stored.
        uint256 available, // How much we can withdraw now.
        uint256 requested // The amount we want to withdraw now.
    );

    /* Admin */

    function init(
        Vertex storage self,
        address token,
        address vault,
        VaultType vType
    ) internal {
        self.vid = newVertexId(token);
        VaultProxyLib.init(self.vid, token, vault, vType);
    }

    // Add this closure to the appropriate homsets for this vertex
    function ensureClosure(Vertex storage self, ClosureId closure) internal {
        if (!closure.contains(self.vid)) return;
        uint256 n = TokenRegLib.numVertices();
        for (uint8 i = 0; i < n; ++i) {
            VertexId neighbor = newVertexId(i);
            if (neighbor == self.vid) continue;
            if (closure.contains(neighbor)) {
                if (self.homSet[neighbor][closure]) {
                    // We've already added this closure
                    return;
                }
                self.homSet[neighbor][closure] = true;
                self.homs[neighbor].push(closure);
            }
        }
    }

    /* Graph Operations */

    // Withdraws tokens from this vertex and builds a closuredist so we know how to distribute the deposit.
    function homSubtract(
        Vertex storage self,
        VertexId other,
        uint256 amount
    ) internal returns (ClosureDist memory dist) {
        ClosureId[] storage homs = self.homs[other];
        // Once we have a vault pointer, no reentrancy is allowed.
        VaultPointer memory vProxy = VaultLib.get(self.vid);
        dist = newClosureDist(homs);

        for (uint256 i = 0; i < homs.length; ++i) {
            uint256 bal = vProxy.balance(homs[i]);
            dist.add(i, bal);
        }

        uint256 withdrawable = vProxy.withdrawable();
        if (withdrawable < amount || dist.total < amount) {
            revert InsufficientWithdraw(
                self.vid,
                other,
                dist.total,
                withdrawable,
                amount
            );
        }
        dist.normalize();

        for (uint256 i = 0; i < homs.length; ++i) {
            vProxy.withdraw(homs[i], dist.scale(i, amount));
        }
        vProxy.commit(); // Commit our changes.
    }

    /// Adds a token balance to this node, splitting the tokens across the subvertices.
    function homAdd(
        Vertex storage self,
        ClosureDist memory dist,
        uint128 amount
    ) internal {
        // Once we have a vault pointer, no reentrancy is allowed.
        VaultPointer memory vProxy = VaultLib.get(self.vid);
        ClosureId[] storage closures = dist.getClosures();
        for (uint256 i = 0; i < dist.closures.length; ++i) {
            vProxy.deposit(closures[i], dist.scale(i, amount));
        }
        vProxy.commit();
    }

    /// Returns the total balance of all closures linking these two vertices.
    function balance(
        Vertex storage self,
        VertexId other
    ) internal view returns (uint256 amount) {
        VaultPointer memory vProxy = VaultLib.get(self.vid);
        Closure[] storage homs = self.homs[other];

        for (uint256 i = 0; i < homs.length; ++i) {
            amount += vProxy.balance(homs[i]);
        }
        // Nothing to commit.
    }
}
