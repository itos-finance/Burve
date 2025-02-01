// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ClosureId} from "./Closure.sol";
import {Store} from "./Store.sol";
import {FullMath} from "./FullMath.sol";
struct AssetStorage {
    mapping(ClosureId => uint256) totalShares;
    mapping(address => mapping(ClosureId => uint256)) shares;
}

/// Bookkeeping for Closure ownership.
library AssetLib {
    /// Add more shares to a user's closure allocation.
    function add(
        address owner,
        ClosureId cid,
        uint256 num,
        uint256 denom
    ) internal returns (uint256 shares) {
        AssetStorage storage assets = Store.assets();
        uint256 total = assets.totalShares[cid];
        if (total == 0) {
            shares = num;
        } else {
            shares = FullMath.mulDiv(num, total, denom);
        }
        assets.shares[owner][cid] += shares;
        assets.totalShares[cid] += shares;
    }

    /// Remove shares from a user's closure allocation.
    function remove(
        address owner,
        ClosureId cid,
        uint256 shares
    ) internal returns (uint256 percentX256) {
        AssetStorage storage assets = Store.assets();
        uint256 total = assets.totalShares[cid];
        if (shares == total) {
            percentX256 = type(uint256).max;
        } else {
            percentX256 = FullMath.mulDivX256(shares, total);
        }
        // Will error on underflow.
        assets.shares[owner][cid] -= shares;
        assets.totalShares[cid] -= shares;
    }
}
