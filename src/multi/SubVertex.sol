// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

type SubVertexId is uint8;

enum VaultType {
    UnImplemented,
    E4626
}

// Holds specific vault information.
struct SubVertex {
    address vault;
    VaultType vType;
    mapping(VertexId => Edge) edges;
}

struct Edge {
    uint256 totalShares;
}

library SubVertexImpl {
    error VaultTypeUnrecognized(VaultType);

    function add(
        SubVertex storage self,
        VertexId other,
        uint256 amount
    ) internal {
        if (self.vType == VaultType.E4626) {
            getE4626(self.vault).add(other, amount);
        } else {
            revert VaultTypeUnrecognized(self.vType);
        }
    }
    function subtract(
        SubVertex storage self,
        VertexId other,
        uint256 amount
    ) internal {
        if (self.vType == VaultType.E4626) {
            getE4626(self.vault).subtract(other, amount);
        } else {
            revert VaultTypeUnrecognized(self.vType);
        }
    }
    function balance(
        SubVertex storage self,
        VertexId other
    ) internal view returns (uint256 amount) {
        if (self.vType == VaultType.E4626) {
            return getE4626(self.vault).balance(other);
        } else {
            revert VaultTypeUnrecognized(self.vType);
        }
    }

    function getE4626(
        address vault
    ) internal returns (VaultE4626 storage proxy) {
        return Store.E4626s()[vault];
    }
}
