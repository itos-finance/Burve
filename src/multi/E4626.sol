// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ClosureId} from "./Closure.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {FullMath} from "./FullMath.sol";
import {VaultPointer, VaultTemp, VaultStorage} from "./VaultProxy.sol";
import {Store} from "./Store.sol";

/** A simple e4626 wrapper that tracks ownership by closureId
 * Note that there are plenty of E4626's that have lockups
 * and we'll have to separate balance from the currently-withdrawable-balance.
 **/
struct VaultE4626 {
    IERC20 token;
    IERC4626 vault;
    uint256 totalVaultShares; // Shares we own in the underlying vault.
    mapping(ClosureId => uint256) shares;
    uint256 totalShares;
}

using VaultE4626Impl for VaultE4626 global;

library VaultE4626Impl {
    /// Thrown when trying to deposit and withdraw from the same vault in one bulk operation.
    error OverlappingOperations(address vault);
    /// Thrown when requesting a balance too large for a given cid.
    error InsufficientBalance(
        address vault,
        ClosureId cid,
        uint256 available,
        uint256 requested
    );

    /** Operational requirements */

    function init(
        VaultE4626 storage self,
        address _token,
        address _vault
    ) internal {
        self.token = IERC20(_token);
        self.vault = IERC4626(_vault);
    }

    // The first function called on vaultProxy creation to prep ourselves for other operations.
    function fetch(
        VaultE4626 storage self,
        VaultTemp memory temp
    ) internal view {
        temp.vars[0] = self.vault.previewRedeem(self.totalVaultShares); // Total assets
        temp.vars[3] = self.vault.previewRedeem(
            self.vault.previewDeposit(1 << 128)
        ); // X128 fee discount factor.
    }

    // Actually make our deposit/withdrawal
    function commit(VaultE4626 storage self, VaultTemp memory temp) internal {
        uint256 assetsToDeposit = temp.vars[1];
        uint256 assetsToWithdraw = temp.vars[2];

        if (assetsToDeposit > 0) {
            if (assetsToWithdraw > 0)
                revert OverlappingOperations(address(self.vault));

            // Temporary approve the deposit.
            self.token.approve(address(self.vault), assetsToDeposit);
            self.totalVaultShares += self.vault.deposit(
                assetsToDeposit,
                address(this)
            );
            self.token.approve(address(self.vault), 0);
        } else if (assetsToWithdraw > 0) {
            // We don't need to hyper-optimize the receiver.
            self.totalVaultShares -= self.vault.withdraw(
                assetsToWithdraw,
                address(this),
                address(this)
            );
        }
    }

    /** Operations used by Vertex */

    function deposit(
        VaultPointer memory self,
        VaultTemp memory temp,
        ClosureId cid,
        uint256 amount
    ) internal {
        // TODO we have to discount the new amount in total assets and new shares
        // by any withdrawal fees.
        uint256 newlyAdding = FullMath.mulDiv(
            temp.vars[1],
            temp.vars[3],
            FullMath.X128
        );
        uint256 totalAssets = temp.vars[0] + newlyAdding;

        uint256 discountedAmount = FullMath.mulDiv(
            amount,
            temp.vars[3],
            FullMath.X128
        );
        VaultStorage storage vaults = Store.vaults();
        VaultE4626 storage vault = vaults.e4626s[self.vid];
        uint256 newShares = FullMath.mulDiv(
            vault.totalShares,
            discountedAmount,
            totalAssets
        );
        vault.shares[cid] += newShares;
        vault.totalShares += newShares;
        temp.vars[1] += amount;
    }

    function withdraw(
        VaultPointer memory self,
        VaultTemp memory temp,
        ClosureId cid,
        uint256 amount
    ) internal {
        // We need to remove the assets we will remove because we're removing from total shares along the way.
        uint256 totalAssets = temp.vars[0] - temp.vars[2];
        // We don't check if we have enough assets for this cid to supply because
        // 1. The shares will underflow if we don't
        // 2. The outer check in vertex should suffice.
        VaultStorage storage vaults = Store.vaults();
        VaultE4626 storage vault = vaults.e4626s[self.vid];
        uint256 sharesToRemove = FullMath.mulDiv(
            vault.totalShares,
            amount,
            totalAssets
        );
        vault.shares[cid] -= sharesToRemove;
        vault.totalShares -= sharesToRemove;
        temp.vars[2] += amount;
    }

    /// Return the most we can withdraw right now.
    function withdrawable(
        VaultE4626 storage self
    ) internal view returns (uint256) {
        return self.vault.maxWithdraw(address(this));
    }

    /// Return the amount of tokens owned by a closure
    function balance(
        VaultPointer memory self,
        VaultTemp memory temp,
        ClosureId cid
    ) internal view returns (uint256 amount) {
        uint256 newlyAdding = FullMath.mulDiv(
            temp.vars[1],
            temp.vars[3],
            FullMath.X128
        );
        uint256 totalAssets = temp.vars[0] + newlyAdding - temp.vars[2];
        VaultStorage storage vaults = Store.vaults();
        VaultE4626 storage vault = vaults.e4626s[self.vid];
        return
            FullMath.mulDiv(vault.shares[cid], totalAssets, vault.totalShares);
    }
}
