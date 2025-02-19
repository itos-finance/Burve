// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ClosureId} from "../Closure.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {TokenRegLib, TokenRegistry} from "../Token.sol";
import {VertexId, newVertexId, Vertex} from "../Vertex.sol";
import {VaultLib, VaultPointer} from "../VaultProxy.sol";
import {Store} from "../Store.sol";
import {Edge} from "../Edge.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {FullMath} from "../../FullMath.sol";
import {AssetStorage, AssetLib} from "../Asset.sol";
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
    error IncorrectAddAmountsList(uint256 tokensGiven, uint256 numTokens);

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
                // We need to add it to the Vertex so we can use it in swaps.
                Store.vertex(v).ensureClosure(cid);
                // Get the before balance.
                VaultPointer memory vPtr = VaultLib.get(v);
                preBalance[i] = vPtr.balance(cid, true);
                uint128 addAmount = amounts[i];
                if (addAmount > 0) {
                    address token = tokenReg.tokens[i];
                    // Get those tokens to this contract.
                    TransferHelper.safeTransferFrom(
                        token,
                        msg.sender,
                        address(this),
                        addAmount
                    );
                    // Move to the vault.
                    vPtr.deposit(cid, addAmount);
                    postBalance[i] = vPtr.balance(cid, false);
                    // Commit the deposit.
                    vPtr.commit();
                    // Set a numeraire if we don't have one yet
                    if (numeraire == address(0)) {
                        numeraire = token;
                        // We use an added token as the numeraire to save gas.
                        numerairePost = postBalance[i];
                    }
                } // Right now unaltered postBalances are 0.
            }
        }
        // When working with vaults and vertices, we handle real token balances.
        // But now that we're about to compute value from prices, we switch to nominal balances.
        IAdjustor adj = Store.adjustor();
        for (uint8 i = 0; i < n; ++i) {
            // Not in a view function so we can cache the value.
            address token = tokenReg.tokens[i];
            adj.cacheAdjustment(token);
            // Round up to increase the original value.
            preBalance[i] = uint128(adj.toNominal(token, preBalance[i], true));
            if (postBalance[i] == 0) {
                postBalance[i] = preBalance[i];
            } else {
                // Round down the increase in value.
                postBalance[i] = uint128(
                    adj.toNominal(token, postBalance[i], false)
                );
            }
        }
        numerairePost = uint128(adj.toNominal(numeraire, numerairePost, false));

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

        emit AddLiquidity(recipient, _closureId, amounts, shares);
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
            VaultPointer memory vPtr = VaultLib.get(v);
            uint128 bal = vPtr.balance(cid, false);
            if (bal == 0) continue;
            // If there are tokens, we withdraw.
            uint256 withdraw = FullMath.mulX256(percentX256, bal, false);
            amounts[i] = withdraw;
            vPtr.withdraw(cid, withdraw);
            vPtr.commit();
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
        AssetStorage storage assets = Store.assets();
        uint256 percentX256 = AssetLib.viewPercentX256(assets, cid, shares);
        uint256 n = TokenRegLib.numVertices();

        uint256[] memory withdrawnAmounts = new uint256[](n);
        for (uint8 i = 0; i < n; ++i) {
            VertexId v = newVertexId(i);
            VaultPointer memory vPtr = VaultLib.get(v);
            uint128 bal = vPtr.balance(cid, false);
            if (bal == 0) continue;
            // If there are tokens, we withdraw.
            uint256 withdraw = FullMath.mulX256(percentX256, bal, false);
            withdrawnAmounts[i] = withdraw;
        }

        return withdrawnAmounts;
    }
}
