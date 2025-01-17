// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "./Storage.sol";
import {VertexId} from "./Vertex.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

library SwapFacet {
    function swap(
        address recipient,
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) internal {
        address uniPool = Store.pools(token0, token1);
        bool zeroForOne = inToken < outToken;
        IUniswapV3Pool(unipool).swap(
            recipient,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            data
        );
    }

    // Things used by swap

    /// Called by a swap to determine price and liquidity.
    function slot0()
        internal
        view
        returns (
            uint160 sqrtPriceX96,
            uint128 narrowLiq,
            int24 narrowLowTick,
            int24 narrowHighTick,
            uint128 wideLiq
        )
    {
        address token0 = IUniswapV3Pool(msg.sender).token0();
        address token1 = IUniswapV3Pool(msg.sender).token1();

        uint128 balance0 = Store.vertex(token0).balance(VertexId.wrap(token1));
        uint128 balance1 = Store.vertex(token1).balance(VertexId.wrap(token0));
        Edge storage edge = Store.edges(token0, token1);
        (narrowLowTick, narrowHighTick) = (edge.narrowLow, edge.narrowHigh);
        (sqrtPriceX96, narrowLiq, wideLiq) = edge.getImplied(
            balance0,
            balance1
        );
    }

    // Called by the unipool when it exchanges one token balance for another.
    function exchange(
        address inToken,
        uint256 inAmount,
        address outToken,
        uint256 outAmount
    ) internal {
        Edge storage edge = Store.edges(inToken, outToken);
        require(address(edge.uniPool) == msg.sender);

        // We send out the outtoken, and give the intoken to the appropriate closures.
        ClosureDist memory dist = Store.vertex(outToken).homSubtract(
            VertexId.wrap(inToken),
            outAmount
        );
        Store.vertex(inToken).homAdd(dist, amount);
    }
}
