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
    function addLiq(
        address recipient,
        bytes32 _closureId,
        address token,
        uint256 amount
    ) internal returns (uint256 shares) {
        ClosureId cid = ClosureId.wrap(_closureId);
        SubVertexId[] memory subIds = cid.getSubIds();
        // We iterate through all the subvertices this uses and get the total balances of the closure we're adding into.
        uint256[] memory balances = new uint256[](subIds.length);
        for (uint256 i = 0; i < subIds; ++i) {
            balances[i] = Store.subVertex(subIds[i]).balance();
        }
        SubVertexId subId = VertexId.wrap(token).getSubId(cid);
        Store.subVertex(subId).add(amount);
        // We can ONLY use the price AFTER adding the token balance or else someone can exploit the
        // old price by doing a huge swap before to increase the value of their deposit.
        uint256 cumulativeValue = 0;
        for (uint256 i = 0; i < subIdx; ++i) {
            // WE NEED TO CACHE USING TRANSIENT.
            cumulativeValue += FullMath.mulX128(
                subIds[i].vertex().priceX128(token),
                balances[i],
                false
            );
        }
        Closure storage closure = Store.closure(cid);
        uint256 newShares = FullMath.mulDiv(
            closure.shares,
            amount,
            cumulativeValue + amount
        );
        closure.add(recipient, newShares);
    }

    function removeLiq(uint256 amount)
}
