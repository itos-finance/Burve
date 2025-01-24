// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";
import {UniV3Edge} from "./UniV3Edge.sol";
import {FullMath} from "./FullMath.sol";

/**
    Contains all information relation to the pool used to swap between two vertices.
 */

struct Edge {
    // TODO: remove?
    IUniswapV3Pool uniPool;
    // Dynamically set with the FeeFacet by an admin, used to collect fees on swaps
    uint24 fee;
    /* Slot 0 and Tick map info */
    // TODO in the future we may make this a list of amplitudes and ticks.
    // For now we just use one range.
    int24 lowTick;
    int24 highTick;
    // To satisfy price transitivity these ticks must also be transitive.
    // e.g. if narrow low of y/x is -10 then z/y must be 10 in order for z/x to commute.
    uint256 amplitude; // The scaling factor between narrow and wide liquidity. Narrow liq = A * wide liq.
    /* non-slot0 info */
    int24 tickSpacing;
    uint24 fee; // Fee rate for swaps
    uint8 feeProtocol; // Fee rate for the protocol
    // accumulated protocol fees in token0/token1 units
    ProtocolFees protocolFees;
}

struct ProtocolFees {
    uint128 token0;
    uint128 token1;
}

using EdgeImpl for Edge global;

library EdgeImpl {
    /// Admin function to set edge parameters.
    /// @dev This is simple because we recalculate the implied price every time.
    /// Just be sure to set the ticks such that the price diagram commutes.
    function setRange(
        Edge storage self,
        uint256 amplitude,
        int24 lowTick,
        int24 highTick
    ) internal {
        self.lowTick = lowTick;
        self.highTick = highTick;
        self.amplitude = amplitude;
    }

    /// Highest level method used by SwapFacet
    function swap(
        Edge storage self,
        address recipient,
        bool zeroForOne,
        uint256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) internal returns (uint256 amount0, uint256 amount1) {
        // Prep the swap.
        UniV3Edge.Slot0 memory slot0 = getSlot0();

        // Calculate the swap amounts and protocolFee
        (int256 amount0, int256 amount1, uint128 protocolFee) = UniV3Edge.swap(
            slot0,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96
        );

        // do the transfers and collect payment
        if (zeroForOne) {
            if (amount1 < 0)
                TransferHelper.safeTransfer(
                    slot0Start.token1,
                    recipient,
                    uint256(-amount1)
                );

            uint256 balance0Before = edge.balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            require(
                balance0Before.add(uint256(amount0)) <= edge.balance0(),
                "IIA"
            );
        } else {
            if (amount0 < 0)
                TransferHelper.safeTransfer(
                    token0,
                    recipient,
                    uint256(-amount0)
                );

            uint256 balance1Before = edge.balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            require(
                balance1Before.add(uint256(amount1)) <= edge.balance1(),
                "IIA"
            );
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            state.sqrtPriceX96,
            state.liquidity,
            state.tick
        );
    }

    /* Methods used by the UniV3Edge */

    /// Called by the UniV3Edge to fetch the information it needs to swap.
    function getSlot0(
        Edge storage self
    )
        internal
        view
        returns (uint160 sqrtPriceX96, uint128 narrowLiq, uint128 wideLiq)
    {
        // We're actually somewhat restrictive on these token amounts.
        // It's mostly okay because we focus on handling stables and blue chips derivatives.
        // If someone actually had 2^128 of a stable, even with 1e18 decimals, all money would be worthless.
        uint160 sqrtPa = getSqrtRatioAtTick(self.lowTick);
        uint160 invSqrtPb = getSqrtRatioAtTick(-self.highTick);
        // These balances will only take up 128 bits.
        uint256 sqrtXWideX64 = sqrt(
            (((uint256(balance0) << 96) + invSqrtPb) << 32) /
                (self.amplitude + 1)
        );
        uint256 sqrtYWideX64 = sqrt(
            (((uint256(balance1) << 96) + sqrtPa) << 32) / (self.amplitude + 1)
        );
        sqrtPriceX96 = (sqrtYWideX64 << 96) / sqrtXWideX64;
        wideLiq = (sqrtYWideX64 * sqrtXWideX64) >> 128;
        narrowLiq = wideLiq * amplitude;
    }

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

        VertexId vid0 = newVertexId(token0);
        VertexId vid1 = newVertexId(token1);
        uint128 balance0 = Store.vertex(vid0).balance(vid1);
        uint128 balance1 = Store.vertex(vid1).balance(vid0);
        Edge storage edge = Store.edges(token0, token1);
        (narrowLowTick, narrowHighTick) = (edge.lowTick, edge.highTick);
        (sqrtPriceX96, narrowLiq, wideLiq) = edge.getImplied(
            balance0,
            balance1
        );
    }

    function nextTick(int24 currentTick, bool isSell /* same as zeroForOne */) internal returns (int24) {
        if (currentTick)
    }

    // Called by the uniEdge when it exchanges one token balance for another.
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

    function balance(
        address token,
        address otherToken
    ) internal returns (uint256 amount) {
        VertexId vid = newVertexId(token);
        VertexId otherVid = newVertexId(otherToken);
        return Store.vertex(vid).balance(otherVid);
    }

    /// Fetch the price implied by these balances on this edge denoted in terms of token1.
    /// @dev This ALWAYS rounds up due to its usage in Add.
    /// @param balance0 This is the balance of token0
    /// @param balance1 This is the balance of token1
    /// @return priceX128 This is the price denoted with token1 as the numeraire.
    function getPriceX128(
        Edge storage self,
        uint128 balance0,
        uint128 balance1
    ) internal view returns (uint256 priceX128) {
        return
            getPriceHelper(
                balance0,
                balance1,
                self.lowTick,
                self.highTick,
                self.amplitude,
                true
            );
    }

    /// Fetch the price implied by these balances on this edge denoted in terms of token0.
    /// @dev This ALWAYS rounds up due to its usage in Add.
    /// @param balance0 This is the balance of token0
    /// @param balance1 This is the balance of token1
    /// @return invPriceX128 This is the price denoted with token0 as the numeraire.
    function getInvPriceX128(
        Edge storage self,
        uint128 balance0,
        uint128 balance1
    ) internal view returns (uint256 invPriceX128) {
        return
            getPriceHelper(
                balance1,
                balance0,
                -self.highTick,
                -self.lowTick,
                self.amplitude,
                true
            );
    }

    /* Helpers */

    function sqrt(uint x) returns (uint y) {
        if (x == 0) return 0;
        else if (x <= 3) return 1;
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /// Helper for computing the price implied by balance1/balance0
    function getPriceHelper(
        uint128 balance0,
        uint128 balance1,
        int24 low,
        int24 high,
        uint256 amp,
        bool roundUp
    ) private pure returns (uint256 priceX128) {
        uint160 sqrtPa = getSqrtRatioAtTick(low);
        uint160 invSqrtPb = getSqrtRatioAtTick(high);
        // See get implied for why this is okay.
        uint256 yWideX128 = (((uint256(balance1) << 96) + sqrtPa) << 32) /
            (self.amplitude + 1);
        uint256 xWideX128 = (((uint256(balance0) << 96) + invSqrtPb) << 32) /
            (self.amplitude + 1);
        return
            roundUp
                ? FullMath.mulDivRoundingUp(yWideX128, 1 << 128, xWideX128)
                : FullMath.mulDiv(yWideX128, 1 << 128, xWideX128);
    }
}
