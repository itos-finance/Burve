// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ClosureId} from "../Closure.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {SafeCast} from "Commons/Math/Cast.sol";
import {TokenRegLib, TokenRegistry} from "../Token.sol";
import {VertexId, newVertexId, Vertex} from "../Vertex.sol";
import {VaultLib, VaultProxy} from "../VaultProxy.sol";
import {Store} from "../Store.sol";
import {Edge} from "../Edge.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {FullMath} from "../../FullMath.sol";
import {AssetLib} from "../Asset.sol";
import {IAdjustor} from "../../integrations/adjustor/IAdjustor.sol";

/*
 @notice The facet for minting and burning liquidity. We will have helper contracts
 that actually issue the ERC20 through these shares.

 @dev To conform to the ERC20 interface, we wrap each subset of tokens
 in their own ERC20 contract with mint functions that call the addLiq and removeLiq
functions here.
*/
contract LiqFacet is ReentrancyGuardTransient {
    error DeMinimisDeposit();
    error VertexLockedInCID(VertexId);
    error IncorrectAddAmountsList(uint256 tokensGiven, uint256 numTokens);
    error ImpreciseCID(uint16 excessBits);
    error SingleBitCID(uint16 singleBit);

    /// @notice Emitted when liquidity is added to a closure
    /// @param recipient The address that received the LP shares
    /// @param closureId The ID of the closure
    /// @param amounts The amounts of each token added
    /// @param shares The number of LP shares minted
    event AddLiquidity(
        address indexed recipient,
        uint16 indexed closureId,
        uint128[] amounts,
        uint256 shares
    );

    /// @notice Emitted when liquidity is removed from a closure
    /// @param recipient The address that received the tokens
    /// @param closureId The ID of the closure
    /// @param amounts The amounts given back on burning of the LP tokens
    /// @param shares The number of LP shares burned
    event RemoveLiquidity(
        address indexed recipient,
        uint16 indexed closureId,
        uint256[] amounts,
        uint256 shares
    );

    function addLiq(
        address recipient,
        uint16 _closureId,
        uint128[] calldata amounts
    ) external nonReentrant returns (uint256 shares) {
        // You need at least two tokens.
        if ((_closureId & (_closureId - 1)) == 0)
            revert SingleBitCID(_closureId);

        ClosureId cid = ClosureId.wrap(_closureId);
        uint256 n = TokenRegLib.numVertices();
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        if (amounts.length != n) {
            revert IncorrectAddAmountsList(amounts.length, n);
        }

        uint128[] memory preBalance = new uint128[](n);
        uint128[] memory postBalance = new uint128[](n);
        address numeraire; // We save one token to use as the value denomination.
        uint128 numerairePost; // The post balance for the numeraire to be used later.

        for (uint8 i = 0; i < n; ++i) {
            VertexId v = newVertexId(i);
            if (cid.contains(v)) {
                Vertex storage vert = Store.vertex(v);
                // We need to add it to the Vertex so we can use it in swaps.
                vert.ensureClosure(cid);
                // We can't add to any CIDs that have a locked vertex.
                if (vert.isLocked()) revert VertexLockedInCID(v);
                // Let's mark that we've visited it.
                _closureId ^= uint16(1 << i);
                uint128 addAmount = amounts[i];
                address token = tokenReg.tokens[i];
                // Get the balances.
                (preBalance[i], postBalance[i]) = getPrePostBalances(
                    v,
                    cid,
                    token,
                    addAmount
                );
                // Set a numeraire if we don't have one yet
                if (
                    (numeraire == address(0)) &&
                    (preBalance[i] != postBalance[i])
                ) {
                    numeraire = token;
                    // We use an added token as the numeraire to save gas.
                    numerairePost = postBalance[i];
                }
            }
        }

        // If after walking through the vertices, the closure has excess bits, the user has a malformed cid
        // that can cause accounting issues when new vertices are added.
        if (_closureId != 0) revert ImpreciseCID(_closureId);

        // We can ONLY use the price AFTER adding the token balance or else someone can exploit the
        // old price by doing a huge swap before to increase the value of their deposit.
        // We denote value in the given token.
        uint256 initialValue;
        uint256 depositValue;
        for (uint256 i = 0; i < n; ++i) {
            if (postBalance[i] != 0) {
                address otherToken = tokenReg.tokens[i];
                if (otherToken == numeraire) {
                    // price = 1
                    initialValue += preBalance[i];
                    depositValue += postBalance[i] - preBalance[i];
                } else {
                    Edge storage e = Store.edge(numeraire, otherToken);
                    uint256 priceX128 = (numeraire < otherToken)
                        ? e.getInvPriceX128(numerairePost, postBalance[i])
                        : e.getPriceX128(postBalance[i], numerairePost);
                    initialValue += FullMath.mulX128(
                        preBalance[i],
                        priceX128,
                        true
                    );
                    depositValue += FullMath.mulX128(
                        postBalance[i] - preBalance[i],
                        priceX128,
                        false
                    );
                }
            }
        }
        if (depositValue == 0) revert DeMinimisDeposit();
        shares = AssetLib.add(recipient, cid, depositValue, initialValue);
        if (shares == 0) revert DeMinimisDeposit();

        emit AddLiquidity(recipient, ClosureId.unwrap(cid), amounts, shares);
    }

    /// @dev This can entirely be done in real amounts.
    function removeLiq(
        address recipient,
        uint16 _closureId,
        uint256 shares
    ) external nonReentrant {
        ClosureId cid = ClosureId.wrap(_closureId);
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        uint256 percentX256 = AssetLib.remove(msg.sender, cid, shares);
        uint256 n = TokenRegLib.numVertices();
        uint256[] memory amounts = new uint256[](n);
        for (uint8 i = 0; i < n; ++i) {
            VertexId v = newVertexId(i);
            VaultProxy memory vProxy = VaultLib.getProxy(v);
            uint128 bal = vProxy.balance(cid, false);
            if (bal == 0) continue;
            // If there are tokens, we withdraw.
            uint256 withdraw = FullMath.mulX256(percentX256, bal, false);
            amounts[i] = withdraw;
            vProxy.withdraw(cid, withdraw);
            vProxy.commit();
            address token = tokenReg.tokens[i];
            TransferHelper.safeTransfer(token, recipient, withdraw);
        }
        emit RemoveLiquidity(recipient, _closureId, amounts, shares);
    }

    function viewRemoveLiq(
        uint16 _closureId,
        uint256 shares
    ) external view returns (uint256[] memory) {
        ClosureId cid = ClosureId.wrap(_closureId);
        uint256 percentX256 = AssetLib.viewPercentX256(cid, shares);
        uint256 n = TokenRegLib.numVertices();
        uint256[] memory withdrawnAmounts = new uint256[](n);
        for (uint8 i = 0; i < n; ++i) {
            VertexId v = newVertexId(i);
            VaultProxy memory vProxy = VaultLib.getProxy(v);
            uint128 bal = vProxy.balance(cid, false);
            if (bal == 0) continue;
            // If there are tokens, we withdraw.
            uint256 withdraw = FullMath.mulX256(percentX256, bal, false);
            withdrawnAmounts[i] = withdraw;
        }

        return withdrawnAmounts;
    }

    /* Helpers */

    /// Fetches the NOMINAL balances before and after a deposit.
    function getPrePostBalances(
        VertexId v,
        ClosureId cid,
        address token,
        uint128 addAmount
    ) private returns (uint128 preBalance, uint128 postBalance) {
        VaultProxy memory vProxy = VaultLib.getProxy(v);
        IAdjustor adj = Store.adjustor();
        // Since we're working with stables and LSTs we know. Nothing will go
        // over 128 bits or else money means nothing.
        preBalance = SafeCast.toUint128(
            adj.toNominal(token, vProxy.balance(cid, true), true)
        );
        if (addAmount > 0) {
            // Get those tokens to this contract.
            TransferHelper.safeTransferFrom(
                token,
                msg.sender,
                address(this),
                addAmount
            );
            // Move to the vault.
            vProxy.deposit(cid, addAmount);
            // Commit the deposit and refetch.
            vProxy.refresh();
            postBalance = SafeCast.toUint128(
                adj.toNominal(token, vProxy.balance(cid, false), false)
            );
        } else {
            postBalance = preBalance;
        }
    }
}
