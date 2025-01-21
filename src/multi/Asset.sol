// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

struct AssetStorage {
    mapping(ClosureId => uint256) totalShares;
    mapping(address => mapping(cid => uint256)) shares;
}

library AssetLib {
    function add(
        address owner,
        ClosureId cid,
        uint256 num,
        uint256 denom
    ) internal returns (uint256 shares) {
        AssetStorage storage assets = Store.assets();
        uint256 total = assets.totalShares[cid];
        shares = FullMath.mulDiv(num, total, denom);
        assets.shares[owner][cid] += shares;
        assets.totalShares[cid] += shares;
    }

    function remove(
        address owner,
        ClosureId cid,
        uint256 shares
    ) internal returns (uint256 percentX256) {
        AssetStorage storage assets = Store.assets();
        uint256 total = assets.totalShares[cid];
        percentX256 = FullMath.mulDivX256(shares, total);
        // Will error on underflow.
        assets.shares[owner][cid] -= shares;
        assets.totalShares[cid] -= shares;
    }
}
