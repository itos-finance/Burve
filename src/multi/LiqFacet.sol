// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/*
 @notice How liquidity to the entire graph is added and removed. A user
 cannot add tokens or liq to each individual pool or vertex by themselves.

 @dev To conform to the ERC20 interface, we wrap each subset of tokens
 in their own ERC20 contract with mint functions that call the addLiq and removeLiq
functions here.
*/
library LiqFacet {
    error TokenNotInClosure(ClosureId cid, address token);

    function addLiq(
        address recipient,
        uint16 _closureId,
        address token,
        uint128 amount
    ) internal returns (uint256 shares) {
        ClosureId cid = ClosureId.wrap(_closureId);
        uint8 idx = TokenRegLib.getIdx(token);
        uint256 n = TokenRegLib.numVertices();

        uint128[] memory preBalance = new uint256[](n);
        uint128 addedBalance = 0;
        for (uint8 i = 0; i < n; ++i) {
            VertexId v = newVertexId(i);
            if (cid.contains(v)) {
                VaultPointer memory vPtr = VaultLib.get(v);
                preBalance[i] = vPtr.balance(cid);
                if (i == idx) {
                    vPtr.deposit(cid, amount);
                    addedBalance = vPtr.balance(cid);
                    // Commit the deposit.
                    vPtr.commit();
                }
            }
        }

        if (addedBalance == 0) revert TokenNotInClosure(cid, token);

        // We can ONLY use the price AFTER adding the token balance or else someone can exploit the
        // old price by doing a huge swap before to increase the value of their deposit.
        uint256 tokenBalance = addedBalance + preBalance[i];
        // We denote value in the given token.
        uint256 cumulativeValue = tokenBalance;
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        for (uint256 i = 0; i < n; ++i) {
            if (i == idx) {
                continue;
            } else if (preBalance[i] != 0) {
                address otherToken = tokenReg.tokens[i];
                Edge storage e = edge(token, otherToken);
                uint256 priceX128 = (token < otherToken)
                    ? e.getInvPriceX128(tokenBalance, preBalance[i])
                    : e.getPriceX128(preBalance[i], tokenBalance);
                cumulativeValue += FullMath.mulX128(preBalance[i], priceX128);
            }
        }
        shares = AssetLib.add(recipient, cid, addedBalance, cumulativeValue);
    }

    function removeLiq(
        address recipient,
        uint16 _closureId,
        uint256 shares,
        bytes calldata continuation
    ) internal {
        ClosureId cid = ClosureId.wrap(_closureId);
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        uint256 percentX256 = AssetLib.remove(msg.sender, cid, shares);
        uint256 n = TokenRegLib.numVertices();
        for (uint8 i = 0; i < n; ++i) {
            VertexId v = newVertexId(i);
            VaultPointer memory vPtr = VaultLib.get(v);
            uint256 withdraw = FullMath.mulX256(
                percentX256,
                vPtr.balance(cid),
                false
            );
            vPtr.withdraw(withdraw);
            vPtr.commit();
            address token = tokenReg.tokens[i];
            TransferHelper.safeTransfer(token, recipient, withdraw);
        }
        // Do we need a continuation?
        if (continuation.length != 0) recipient.staticcall(continuation);
    }

    function approve(address spender, uint256 amount) external returns (bool);
}
