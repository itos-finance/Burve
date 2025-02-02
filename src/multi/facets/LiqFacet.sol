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
import {FullMath} from "../FullMath.sol";
import {AssetLib} from "../Asset.sol";
import {BurveFacetBase} from "./Base.sol";

/*
 @notice The facet for minting and burning liquidity. We will have helper contracts
 that actually issue the ERC20 through these shares.

 @dev To conform to the ERC20 interface, we wrap each subset of tokens
 in their own ERC20 contract with mint functions that call the addLiq and removeLiq
functions here.
*/
contract LiqFacet is ReentrancyGuardTransient, BurveFacetBase {
    error TokenNotInClosure(ClosureId cid, address token);
    error IncorrectAddAmountsList(uint256 tokensGiven, uint256 numTokens);

    // Add liquidity in a simple way with just one token.
    // This is a cheap and convenient method for small deposits that won't move the peg very much.
    function addLiq(
        address recipient,
        uint16 _closureId,
        address token,
        uint128 amount
    ) external nonReentrant validToken(token) returns (uint256 shares) {
        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );

        ClosureId cid = ClosureId.wrap(_closureId);
        // This validates the token is registered.
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
        console.log("addedBalance", addedBalance);

        // We can ONLY use the price AFTER adding the token balance or else someone can exploit the
        // old price by doing a huge swap before to increase the value of their deposit.
        // We denote value in the given token.
        uint256 cumulativeValue = preBalance[idx]; // The denom is the value sans the deposit.
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
                console.log("bl;ash");
                cumulativeValue += FullMath.mulX128(
                    preBalance[i],
                    priceX128,
                    true
                );
            }
        }
        console.log("cumulative value", cumulativeValue);
        shares = AssetLib.add(recipient, cid, addedBalance, cumulativeValue);
    }

    /// A true liquidity add to all vertices in a given CID.
    /// @dev Use then when depositing a large amount of liquidity to avoid depegging and getting arb'd.
    /// @param recipient Who owns the liquidity for the CID at the end.
    /// @param _closureId The CID you would like to add liquidity to.
    /// @param amounts A list of token amounts that we want to add. One for each token in the Simplex, NOT your CID.
    /// Any token amounts given for a vertex not in the CID is ignored.
    /// You can conveniently supply [amount, amount, amount, ...] if you want to supply the same amount to all vertices
    /// in your CID.
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
        require(amounts.length == n, "ALN");
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
                    // Set a numeraire if we don't have one
                    if (numeraire == address(0)) {
                        numeraire = token;
                        numerairePost = postBalance[i];
                    }
                } else {
                    postBalance[i] = preBalance[i];
                }
            }
        }

        // We can ONLY use the price AFTER adding the token balances or else someone can exploit the
        // old price by doing a huge swap before to increase the value of their deposit.
        // We denote value in the first token we received.
        uint256 initialValue;
        uint256 depositValue;
        for (uint256 i = 0; i < n; ++i) {
            if (postBalance[i] != 0) {
                address otherToken = tokenReg.tokens[i];
                if (otherToken == numeraire) {
                    // price = 1
                    console.log("numeraire part");
                    initialValue += preBalance[i];
                    depositValue += postBalance[i] - preBalance[i];
                } else {
                    Edge storage e = Store.edge(numeraire, otherToken);
                    console.log("numpost", numerairePost);
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
        shares = AssetLib.add(recipient, cid, depositValue, initialValue);
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
