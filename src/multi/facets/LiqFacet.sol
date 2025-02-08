// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ClosureId} from "../Closure.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/utils/ReentrancyGuardTransient.sol";
import {TokenRegLib, TokenRegistry} from "../Token.sol";
import {VertexId, newVertexId, Vertex} from "../Vertex.sol";
import {VaultLib, VaultPointer} from "../VaultProxy.sol";
import {Store} from "../Store.sol";
import {Edge} from "../Edge.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {FullMath} from "../FullMath.sol";
import {AssetLib} from "../Asset.sol";

/*
 @notice The facet for minting and burning liquidity. We will have helper contracts
 that actually issue the ERC20 through these shares.

 @dev To conform to the ERC20 interface, we wrap each subset of tokens
 in their own ERC20 contract with mint functions that call the addLiq and removeLiq
functions here.
*/
contract LiqFacet is ReentrancyGuardTransient {
    error TokenNotInClosure(ClosureId cid, address token);

    function addLiq(
        address recipient,
        uint16 _closureId,
        address token,
        uint128 amount
    ) external nonReentrant returns (uint256 shares) {
        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );

        ClosureId cid = ClosureId.wrap(_closureId);
        uint8 idx = TokenRegLib.getIdx(token);
        uint256 n = TokenRegLib.numVertices();

        uint128[] memory preBalance = new uint128[](n);
        uint128 tokenBalance = 0;
        for (uint8 i = 0; i < n; ++i) {
            VertexId v = newVertexId(i);
            if (cid.contains(v)) {
                // We need to add it to the Vertex so we can use it in swaps.
                Store.vertex(v).ensureClosure(cid);
                // And we need to add it to the vault.
                VaultPointer memory vPtr = VaultLib.get(v);
                preBalance[i] = vPtr.balance(cid, true);
                if (i == idx) {
                    vPtr.deposit(cid, amount);
                    tokenBalance = vPtr.balance(cid, false);
                    // Commit the deposit.
                    vPtr.commit();
                }
            }
        }

        // Check we actually deposited.
        if (tokenBalance == 0) revert TokenNotInClosure(cid, token);
        // Get the amount we added rounded down.
        uint256 addedBalance = tokenBalance - preBalance[idx];

        // We can ONLY use the price AFTER adding the token balance or else someone can exploit the
        // old price by doing a huge swap before to increase the value of their deposit.
        // We denote value in the given token.
        uint256 cumulativeValue = preBalance[idx];
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        for (uint256 i = 0; i < n; ++i) {
            if (i == idx) {
                continue;
            } else if (preBalance[i] != 0) {
                address otherToken = tokenReg.tokens[i];
                Edge storage e = Store.edge(token, otherToken);
                uint256 priceX128 = (token < otherToken)
                    ? e.getInvPriceX128(tokenBalance, preBalance[i])
                    : e.getPriceX128(preBalance[i], tokenBalance);
                cumulativeValue += FullMath.mulX128(
                    preBalance[i],
                    priceX128,
                    true
                );
            }
        }
        shares = AssetLib.add(recipient, cid, addedBalance, cumulativeValue);
    }

    function removeLiq(
        address recipient,
        uint16 _closureId,
        uint256 shares
    ) external nonReentrant {
        ClosureId cid = ClosureId.wrap(_closureId);
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        uint256 percentX256 = AssetLib.remove(msg.sender, cid, shares);
        uint256 n = TokenRegLib.numVertices();
        for (uint8 i = 0; i < n; ++i) {
            VertexId v = newVertexId(i);
            VaultPointer memory vPtr = VaultLib.get(v);
            uint128 bal = vPtr.balance(cid, false);
            if (bal == 0) continue;
            // If there are tokens, we withdraw.
            uint256 withdraw = FullMath.mulX256(percentX256, bal, false);
            vPtr.withdraw(cid, withdraw);
            vPtr.commit();
            address token = tokenReg.tokens[i];
            TransferHelper.safeTransfer(token, recipient, withdraw);
        }
    }
}
