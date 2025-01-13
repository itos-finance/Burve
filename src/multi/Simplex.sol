// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/*
    A simplex contains multiple closures and multiple vertices.
    It is effectively a summary of the whole graph and users
*/

library SwapFacet {
    function swap(
        address token0,
        address token1,
        uint256 amount,
        bool exactIn
    ) internal {
        address uniPool = pools[token0][token1];
        UniswapV3(unipool).swap(amount, exactIn);
    }

    // Things used by swap

    /// Called by a swap to determine price and liquidity.
    function slot0()
        internal
        returns (uint160 sqrtPriceX96, uint128 wideLiq, uint128 narrowLiq)
    {
        (address token0, address token1) = getTokens(msg.sender);
        uint256 balance0 = Store.vertices()[token0].queryBalance();
        uint256 balance1 = Store.vertices()[token1].queryBalance();
        (sqrtPriceX96, wideLiq, narrowLiq) = calcPriceAndLiqs(
            token0,
            token1,
            balance0,
            balance1
        );
    }

    // Called by the unipool when it gets a token balance.
    function addHomBalance(
        address token,
        address other,
        uint256 amount
    ) internal {
        Store.vertices()[token].add(other, amount);
    }

    function removeHomBalance(
        address token,
        address other,
        uint256 amount
    ) internal {
        Store.vertices()[token].remove(other, amount);
    }
}

library LiqFacet {
    function mint(address recipient, uint256 amount) {
        /// Do the same thing as addliq but through a callback.
    }

    function addLiq(
        address recipient,
        bytes32 _closureId,
        address token,
        uint256 amount
    ) {
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
    }
}
