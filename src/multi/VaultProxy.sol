// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {VertexId} from "./Vertex.sol";
import {VaultE4626, VaultE4626Impl} from "./E4626.sol";
import {Store} from "./Store.sol";
import {ClosureId} from "./Closure.sol";

// The number of temporary variables used by vaults. See VaultTemp.
uint256 constant NUM_VAULT_VARS = 4;

enum VaultType {
    UnImplemented,
    E4626
}

// Holds overall vault information.
struct VaultStorage {
    mapping(VertexId => VaultType) vTypes;
    mapping(VertexId => VaultE4626) e4626s;
}

library VaultLib {
    // Thrown when a vault already exists for the verted id we're initializing.
    error VaultExists(VertexId);
    error VaultTypeNotRecognized(VaultType);
    // Thrown during a get if the vault can't be found.
    error VaultNotFound(VertexId);

    /// Initialize the underlying vault for a vertex.
    function init(
        VertexId vid,
        address token,
        address vault,
        VaultType vType
    ) internal {
        VaultStorage storage vaults = Store.vaults();
        if (vaults.vTypes[vid] != VaultType.UnImplemented)
            revert VaultExists(vid);
        vaults.vTypes[vid] = vType;
        if (vType == VaultType.E4626) {
            vaults.e4626s[vid].init(token, vault);
        } else {
            revert VaultTypeNotRecognized(vType);
        }
    }

    /// Fetch a VaultPointer for the vertex's underlying vault.
    function get(
        VertexId vid
    ) internal view returns (VaultPointer memory vPtr) {
        VaultStorage storage vaults = Store.vaults();
        vPtr.vType = vaults.vTypes[vid];
        if (vPtr.vType == VaultType.E4626) {
            VaultE4626 storage v = vaults.e4626s[vid];
            assembly {
                mstore(vPtr, v.slot) // slotAddress is the first field.
            }
            v.fetch(vPtr.temp);
        } else {
            revert VaultNotFound(vid);
        }
    }
}

/// An in-memory struct for holding temporary variables used by the vault implementations
struct VaultTemp {
    uint256[NUM_VAULT_VARS] vars;
}

/// An in-memory struct for dynamically dispatching to different vaultTypes
struct VaultPointer {
    bytes32 slotAddress;
    VaultType vType;
    VaultTemp temp;
}

using VaultPointerImpl for VaultPointer global;

library VaultPointerImpl {
    error VaultTypeUnrecognized(VaultType);

    /// Queue up a deposit for a given cid.
    function deposit(
        VaultPointer memory self,
        ClosureId cid,
        uint256 amount
    ) internal {
        if (self.vType == VaultType.E4626) {
            getE4626(self).deposit(self.temp, cid, amount);
        } else {
            revert VaultTypeUnrecognized(self.vType);
        }
    }

    /// Queue up a withdrawal for a given cid.
    function withdraw(
        VaultPointer memory self,
        ClosureId cid,
        uint256 amount
    ) internal {
        if (self.vType == VaultType.E4626) {
            getE4626(self).withdraw(self.temp, cid, amount);
        } else {
            revert VaultTypeUnrecognized(self.vType);
        }
    }

    /// Query the most tokens that can actually be withdrawn.
    /// @dev This is the only one that makes a direct call to the vault,
    /// so be careful it returns a value that does not account for any pending deposits.
    function withdrawable(
        VaultPointer memory self
    ) internal view returns (uint256 _withdrawable) {
        if (self.vType == VaultType.E4626) {
            return getE4626(self).withdrawable();
        } else {
            revert VaultTypeUnrecognized(self.vType);
        }
    }

    /// Query the balance available to the given cid.
    function balance(
        VaultPointer memory self,
        ClosureId cid,
        bool roundUp
    ) internal view returns (uint128 amount) {
        if (self.vType == VaultType.E4626) {
            return getE4626(self).balance(self.temp, cid, roundUp);
        } else {
            revert VaultTypeUnrecognized(self.vType);
        }
    }

    /// Query the total balance of all the given cids.
    function totalBalance(
        VaultPointer memory self,
        ClosureId[] storage cids,
        bool roundUp
    ) internal view returns (uint128 amount) {
        if (self.vType == VaultType.E4626) {
            return getE4626(self).totalBalance(self.temp, cids, roundUp);
        } else {
            revert VaultTypeUnrecognized(self.vType);
        }
    }

    /// Because vaults batch operations together, they do one final operation
    /// as needed during the commit step.
    function commit(VaultPointer memory self) internal {
        if (self.vType == VaultType.E4626) {
            getE4626(self).commit(self.temp);
        } else {
            revert VaultTypeUnrecognized(self.vType);
        }
    }

    /// A convenience function that forces a commit and re-fetches from the underlying vault.
    function refresh(VaultPointer memory self) internal {
        if (self.vType == VaultType.E4626) {
            VaultE4626 storage v = getE4626(self);
            v.commit(self.temp);
            clearTemp(self);
            v.fetch(self.temp);
        }
    }

    /* helpers */

    function getE4626(
        VaultPointer memory self
    ) private pure returns (VaultE4626 storage proxy) {
        assembly {
            proxy.slot := mload(self)
        }
    }

    function clearTemp(VaultPointer memory self) private {
        for (uint256 i = 0; i < NUM_VAULT_VARS; ++i) {
            self.temp.vars[i] = 0;
        }
    }
}
