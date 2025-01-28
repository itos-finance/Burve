// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ClosureId} from "./Closure.sol";
import {Store} from "./Store.sol";
import {FullMath} from "./FullMath.sol";
import {console2 as console} from "forge-std/console2.sol";

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
            console.log("num,", num);
            console.log("total,", total);
            console.log("denom,", denom);
            shares = FullMath.mulDiv(num, total, denom);
            console.log("share", shares);
        }
        assets.shares[owner][cid] += shares;
        assets.totalShares[cid] += shares;
    }

    /// Remove shares frmo a user's closure allocation.
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
            // percentX256 = FullMath.mulDivX256(shares, total);
            percentX256 = FullMath.mulDiv(shares, 1 << 255, total) << 1;
        }
        // Will error on underflow.
        assets.shares[owner][cid] -= shares;
        assets.totalShares[cid] -= shares;
    }
}
