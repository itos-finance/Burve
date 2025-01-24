// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {FullMath} from "./FullMath.sol";
import {VertexId} from "./Vertex.sol";
import {Store} from "./Store.sol";
import {TokenRegistry} from "./Token.sol";

type ClosureId is uint16;

using ClosureIdImpl for ClosureId global;

uint256 constant SCALE_FACTOR = 1 << 128; // Using 128 bits instead of 256 for scaling

function newClosureId(address[] memory tokens) returns (ClosureId) {
    uint16 cid = 0;
    TokenRegistry storage tokenReg = Store.tokenRegistry();
    for (uint256 i = 0; i < tokens.length; ++i) {
        uint16 idx = uint16(1 << tokenReg.tokenIdx[tokens[i]]);
        cid |= idx;
    }
    return ClosureId.wrap(cid);
}

library ClosureIdImpl {
    function contains(
        ClosureId self,
        VertexId vid
    ) internal pure returns (bool) {
        return (ClosureId.unwrap(self) & VertexId.unwrap(vid)) != 0;
    }
}

// In-memory data structure for stores a probability distribution over closures.
struct ClosureDist {
    bytes32 closurePtr;
    uint256 totalWeight;
    uint256[] weights;
}

// Thrown when a closure dist that is already normalized gets normalized again.
error AlreadyNormalized();
// Thrown when trying to scale with an unnormalized dist.
error NotNormalized();

library ClosureDistImpl {
    function newClosureDist(
        ClosureId[] storage closures
    ) internal returns (ClosureDist memory dist) {
        assembly {
            mstore(dist, closures.slot)
        }
        dist.weights = new uint256[](closures.length);
        dist.totalWeight = 0;
    }

    // @dev This denormalizes a distribution.
    function add(
        ClosureDist memory self,
        uint256 idx,
        uint256 weight
    ) internal pure {
        self.weights[idx] += weight;
        self.totalWeight += weight;
    }

    function normalize(ClosureDist memory self) internal pure {
        if (self.totalWeight == 0) revert AlreadyNormalized();
        for (uint256 i = 0; i < self.weights.length; ++i) {
            self.weights[i] = FullMath.mulDiv(
                self.weights[i],
                SCALE_FACTOR,
                self.totalWeight
            );
        }
        self.totalWeight = 0;
    }

    function scale(
        ClosureDist memory self,
        uint256 idx,
        uint256 amount
    ) internal pure returns (uint256 scaled) {
        if (self.totalWeight != 0) revert NotNormalized();
        scaled = FullMath.mulDiv(self.weights[idx], amount, SCALE_FACTOR);
    }

    function getClosures(
        ClosureDist memory self
    ) internal pure returns (ClosureId[] storage closures) {
        assembly {
            closures.slot := mload(self)
        }
    }
}
