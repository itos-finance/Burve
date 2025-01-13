// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

type ClosureId is bytes32;

struct Closure {
    address[] tokens;
}

using ClosureImpl for Closure global;

library ClosureImpl {}

// In-memory data structure for stores a probability distribution over closures.
struct ClosureDist {
    ClosureId[] closures;
    uint256[] weights;
    uint256 totalWeight;
    SubVertexId group;
}

struct ClosureDistImpl {
    function add(ClosureDist memory self, ClosureId closure, uint256 weight) {
        self.closures
    }
}
