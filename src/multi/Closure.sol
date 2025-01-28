// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {FullMath} from "./FullMath.sol";
import {VertexId} from "./Vertex.sol";
import {Store} from "./Store.sol";
import {TokenRegistry} from "./Token.sol";
import {console2} from "forge-std/console2.sol";

type ClosureId is uint16;

using ClosureIdImpl for ClosureId global;

function newClosureId(address[] memory tokens) view returns (ClosureId) {
    uint16 cid = 0;
    TokenRegistry storage tokenReg = Store.tokenRegistry();
    for (uint256 i = 0; i < tokens.length; ++i) {
        uint16 idx = uint16(1 << tokenReg.tokenIdx[tokens[i]]);
        cid |= idx;
    }
    return ClosureId.wrap(cid);
}

library ClosureIdImpl {
    function isEq(
        ClosureId self,
        ClosureId other
    ) internal pure returns (bool) {
        return ClosureId.unwrap(self) == ClosureId.unwrap(other);
    }

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

function newClosureDist(
    ClosureId[] storage closures
) view returns (ClosureDist memory dist) {
    bytes32 ptr;
    assembly {
        ptr := closures.slot
    }
    dist.closurePtr = ptr;
    dist.weights = new uint256[](closures.length);
    dist.totalWeight = 0;
}

using ClosureDistImpl for ClosureDist global;

library ClosureDistImpl {
    // Thrown when a closure dist that is already normalized gets normalized again.
    error AlreadyNormalized(); // Shadowable.
    // Thrown when trying to scale with an unnormalized dist.
    error NotNormalized(); // Shadowable.

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
            uint256 originalWeight = self.weights[i];
            console2.log("Index:", i);
            console2.log("Original Weight:", originalWeight);
            console2.log("total weight", self.totalWeight);
            // TODO add not getting done: totalWeight missing
            uint256 scaledWeight = originalWeight == self.totalWeight
                ? type(uint256).max - 1
                : FullMath.mulDivX256(originalWeight, self.totalWeight);
            console2.log("Scaled Weight:", scaledWeight);

            self.weights[i] = scaledWeight;
        }
        console2.log("Total Weight before reset:", self.totalWeight);
        self.totalWeight = 0;
        console2.log("Total Weight after reset:", self.totalWeight);
    }

    // Scale an amount by the relative weight of idx in this distribution
    function scale(
        ClosureDist memory self,
        uint256 idx,
        uint256 amount,
        bool roundUp
    ) internal pure returns (uint256 scaled) {
        if (self.totalWeight != 0) revert NotNormalized();
        scaled = FullMath.mulX256(self.weights[idx], amount, roundUp);
    }

    function getClosures(
        ClosureDist memory self
    ) internal pure returns (ClosureId[] storage closures) {
        // The first slot in self is the closurePtr
        assembly {
            closures.slot := mload(self)
        }
    }
}
