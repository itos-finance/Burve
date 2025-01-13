// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

uint256 constant MAX_SUBS = 16;

type VertexId is address;

import {SubVertex, VaultType} from "./SubVertex.sol";

/**
 * Vertices supply tokens to the trading pools. These track how the tokens they hold are split across subvertices.
 * The subvertices track how their tokens are split across closures.
 */
struct Vertex {
    VertexId token;
    // The tokens available at this vertex are the sum of all the tokens in these subvertices
    SubVertex[] subs;
}

using VertexIdImpl for VertexId global;
using VertexImpl for Vertex global;

library VertexIdImpl {
    function join(
        VertexId self,
        uint8 idx
    ) internal returns (SubVertexId subId) {
        uint8 base = Store.tokenRegistry().tokenIdx[VertexId.unwrap(self)];
        subId = SubVertexId.unwrap((idx << 4) + base);
    }
}

/* A vertex encapsulates the information of a single token */
library VertexImpl {
    /* Admin */

    function init(Vertex storage self, address token) internal {
        self.token = VertexId.wrap(token);
    }

    function addSubVertex(
        Vertex storage self,
        address vault,
        VaultType vType
    ) internal {
        uint256 idx = self.subs.length;
        if (idx + 1 >= MAX_SUBS)
            revert AtSubVertexCapacity(VertexId.unwrap(self.token));
        self.subs.push();
        self.subs[idx].init(subId, vault, vType);
    }

    /* Graph Operations */

    // Withdraws tokens from this vertex and builds a closuredist so we know how to distribute the deposit.
    function homSubtract(
        Vertex storage self,
        VertexId other,
        uint256 amount
    ) internal returns (ClosureDist memory dist) {
        uint256 totalBalance = 0;
        uint256[] balances = new uint256[](self.subs.length);
        for (uint256 i = 0; i < self.subs.length; ++i) {
            balances[i] = self.subs[i].balance(other);
            totalBalance += balances[i];
        }
        uint256 cumAllocation;
        for (uint256 i = 0; i < balances.length; ++i) {
            uint256 allocation;
            totalBalance -= balances[i];
            if (totalBalance == 0) {
                // This could happen before the last subvertex
                allocation = amount - cumAllocation;
                self.vaults.homSubtract(other, allocation, dist);
                break;
            } else {
                allocation = FullMath.mulDiv(amount, balances[i], totalBalance);
                cumAllocation += allocation;
                self.vaults.homSubtract(other, allocation, dist);
            }
        }
    }

    /// Adds a token balance to this node, splitting the tokens across the subvertices.
    function homAdd(
        Vertex storage self,
        ClosureDist memory dist,
        uint128 amount
    ) internal {
        (ClosureDist[] memory subDists, uint256[] splitX256) = dist.groupBy(
            self.token
        );
        for (uint256 i = 0; i < self.subDists.length; ++i) {
            uint256 subAmount = FullMath.mulX256(splitX256, amount);
            SubVertexId subId = subDists[i].getSubVertexId();
            self.subs[subId.idx()].homAdd(subDists[i], subAmount);
        }
    }

    /// Returns the total balance of all closures linking these two vertices.
    function balance(
        Vertex storage self,
        VertexId other
    ) internal view returns (uint256 amount) {
        for (uint256 i = 0; i < self.subs.length; ++i) {
            amount += self.subs[i].balance(other);
        }
    }
}
