// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {VertexId, VertexLib} from "./Id.sol";
import {ReserveLib} from "./Reserve.sol";
import {VaultLib, VaultProxy, VaultType} from "./VaultProxy.sol";
import {ClosureId} from "../closure/Id.sol";
import {SimplexLib} from "../Simplex.sol";
import {FullMath} from "../../FullMath.sol";

/**
 * Vertices supply tokens to the closures. Each tracks the total balance of one token.
 * Vertices work in real balances.
 */
struct Vertex {
    VertexId vid;
    bool _isLocked;
}

using VertexImpl for Vertex global;

library VertexImpl {
    /// Thrown when a vertex is locked so it cannot accept more deposits, or swaps out.
    error VertexLocked(VertexId vid);
    /// Thrown when the vault has a withdraw limit lower than the requested amount.
    error WithdrawLimited(VertexId vid, uint256 amount);
    /// Emitted when the pool is holding insufficient balance for a token.
    /// This should never happen unless something is really wrong, like a vault
    /// losing money. In such an event check what is wrong, the severity, and either
    /// top up the pool or lock the vertex until resolved.
    /// @dev We don't revert because the swap is not the issue and wouldn't resolve
    /// the underlying problem.
    event InsufficientBalance(
        VertexId vid,
        ClosureId cid,
        uint256 targetReal,
        uint256 realBalance
    );

    /* Admin */

    function init(
        Vertex storage self,
        VertexId vid,
        address token,
        address vault,
        VaultType vType
    ) internal {
        self.vid = vid;
        VaultLib.add(self.vid, token, vault, vType);
    }

    /* Closure Operations */

    /// Closures call this before operating on any Vertex. Called on all vertices in a closure when value changes.
    /// Like an overgrown lawn, we typically have more tokens than needed for a given closure.
    /// Given the target REAL balance, we move shares to the reserve and
    /// return the shares moved so the closure can add it as earnings to its depositors.
    /// @dev The shares earned are MOVED TO THE RESERVE.
    /// @param targetReal The amount of tokens the cid expects to have in this token.
    /// @return reserveSharesEarned - The amount of shares moved to the reserve for non-bgt values to claim later.
    /// @return bgtEarned - The amount of bgt earned by the bgt values from exchanging.
    /// @return unspentShares - The amount of reserve shares for earnings not spent in the bgt exchange.
    function trimBalance(
        Vertex storage self,
        ClosureId cid,
        uint256 targetReal,
        uint256 value,
        uint256 bgtValue
    )
        internal
        returns (
            uint256 reserveSharesEarned,
            uint256 bgtEarned,
            uint256 unspentShares
        )
    {
        VaultProxy memory vProxy = VaultLib.getProxy(self.vid);
        uint256 realBalance = vProxy.balance(cid, false);
        // We don't error and instead emit in this scenario because clearly the vault is not working properly but if
        // we error users can't withdraw funds. Instead the right response is to lock and move vaults immediately.
        if (targetReal > realBalance) {
            emit InsufficientBalance(self.vid, cid, targetReal, realBalance);
            return (0, 0, 0);
        }
        uint256 residualReal = realBalance - targetReal;
        uint256 bgtResidual = FullMath.mulDiv(residualReal, bgtValue, value);
        // Now we move the shares from the cid vault to the reserve.
        bool validWithdraw = vProxy.withdraw(cid, residualReal);
        reserveSharesEarned = ReserveLib.deposit(
            vProxy,
            self.vid,
            residualReal - bgtResidual
        );
        if (bgtResidual > 0) {
            uint256 unspent;
            if (validWithdraw) {
                (bgtEarned, unspent) = SimplexLib.viewBgtExchange(
                    self.vid.idx(),
                    bgtResidual
                );
            } else {
                // By not spending when withdraws will fail, we avoid withdraw/depositing
                // and instead are just moving shares from the vault to the reserve.
                unspent = bgtResidual;
            }
            unspentShares = ReserveLib.deposit(vProxy, self.vid, unspent);
        }
        vProxy.commit();
        // Now that we've commited we have the tokens to exchange.
        SimplexLib.bgtExchange(self.vid.idx(), bgtResidual);
    }

    /// A few version of trim that just returns the real balances earned.
    function viewTrim(
        Vertex storage self,
        ClosureId cid,
        uint256 targetReal,
        uint256 value,
        uint256 bgtValue
    )
        internal
        view
        returns (uint256 realTokensEarned, uint256 bgtRealResidual)
    {
        VaultProxy memory vProxy = VaultLib.getProxy(self.vid);
        uint256 realBalance = vProxy.balance(cid, false);
        if (targetReal > realBalance) {
            return (0, 0);
        }
        uint256 residualReal = realBalance - targetReal;
        bgtRealResidual = FullMath.mulDiv(residualReal, bgtValue, value);
        realTokensEarned = residualReal - bgtRealResidual;
    }

    /// Closures deposit a real amount into this Vertex.
    function deposit(
        Vertex storage self,
        ClosureId cid,
        uint256 amount
    ) internal {
        VaultProxy memory vProxy = VaultLib.getProxy(self.vid);
        validateLock(self, vProxy);
        vProxy.deposit(cid, amount);
        vProxy.commit();
    }

    /// A barebones version of deposit that does not handle vproxy commit timing or lock checks.
    /// @dev Used by admin functions that have to deposit into multiple closures at once.
    function deposit(
        Vertex storage, // Not needed but conforms to the interface.
        VaultProxy memory vProxy,
        ClosureId cid,
        uint256 amount
    ) internal {
        vProxy.deposit(cid, amount);
    }

    /// Withdraw a specified amount from the holdings of a given closure.
    /// @dev If checkLock is true, it will revert if the vertex is locked.
    /// @dev If the withdraw is limited by withdraw limits, it will revert.
    function withdraw(
        Vertex storage self,
        ClosureId cid,
        uint256 amount,
        bool checkLock
    ) internal {
        VaultProxy memory vProxy = VaultLib.getProxy(self.vid);
        if (checkLock) {
            validateLock(self, vProxy);
        }
        require(
            vProxy.withdraw(cid, amount),
            WithdrawLimited(self.vid, amount)
        );
        vProxy.commit();
    }

    /// Returns the token balance of a closure.
    function balance(
        Vertex storage self,
        ClosureId cid,
        bool roundUp
    ) internal view returns (uint256 amount) {
        VaultProxy memory vProxy = VaultLib.getProxy(self.vid);
        amount = vProxy.balance(cid, roundUp);
        // Nothing to commit.
    }

    /* Lock operations */

    function lock(Vertex storage self) internal {
        self._isLocked = true;
    }

    function unlock(Vertex storage self) internal {
        self._isLocked = false;
    }

    function isLocked(Vertex storage self) internal view returns (bool) {
        return self._isLocked;
    }

    function validateLock(
        Vertex storage self,
        VaultProxy memory vProxy
    ) internal {
        if (!vProxy.isValid()) lock(self);
        require(!self._isLocked, VertexLocked(self.vid));
    }
}
