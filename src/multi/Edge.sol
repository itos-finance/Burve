// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";
import {UniV3Edge} from "./UniV3Edge.sol";
import {FullMath} from "./FullMath.sol";
import {TransferHelper} from "../TransferHelper.sol";
import {IUniswapV3SwapCallback} from "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {Vertex, VertexId, newVertexId, VertexImpl} from "./Vertex.sol";
import {Store} from "./Store.sol";
import {ClosureDist} from "./Closure.sol";

/**
    Contains all information relation to the pool used to swap between two vertices.
 */

struct Edge {
    // TODO: remove?
    // IUniswapV3Pool uniPool;
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

struct SwapState {
    uint160 sqrtPriceX96;
    int24 tick;
    uint128 liquidity;
}

event Swap(
    address indexed sender,
    address indexed recipient,
    int256 amount0,
    int256 amount1,
    uint160 sqrtPriceX96,
    uint128 liquidity,
    int24 tick
);

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

    /// Returns the liquidity at a given tick
    // TODO verify this is expected
    function getLiquidity(
        Edge storage self,
        int24 tick
    ) internal view returns (uint128 liquidity) {
        // Get the slot0 info which contains our liquidity values
        (, uint128 narrowLiq, uint128 wideLiq) = getSlot0(self);

        // If we're between the low and high ticks, we use the narrow liquidity
        // Otherwise we use the wide liquidity
        if (tick >= self.lowTick && tick <= self.highTick) {
            return narrowLiq;
        } else {
            return wideLiq;
        }
    }

    /// Returns the next initialized tick in the given direction
    function nextTick(
        Edge storage self,
        int24 tick,
        bool zeroForOne
    ) internal view returns (int24) {
        if (zeroForOne) {
            return tick <= self.lowTick ? self.lowTick : self.highTick;
        } else {
            return tick >= self.highTick ? self.highTick : self.lowTick;
        }
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
        (uint160 sqrtPrice, uint128 narrowLiq, uint128 wideLiq) = getSlot0(
            self
        );
        UniV3Edge.Slot0 memory slot0;
        slot0.token0 = msg.sender;
        slot0.token1 = address(this);
        slot0.tick = TickMath.getTickAtSqrtRatio(sqrtPrice);
        slot0.sqrtPriceX96 = sqrtPrice;
        slot0.feeProtocol = self.feeProtocol;
        slot0.liquidity = narrowLiq;
        slot0.fee = self.fee;
        SwapState memory state;

        // Calculate the swap amounts and protocolFee
        (int256 amount0Int, int256 amount1Int, uint128 protocolFee) = UniV3Edge
            .swap(
                self,
                slot0,
                zeroForOne,
                int256(amountSpecified),
                sqrtPriceLimitX96
            );

        // do the transfers and collect payment
        if (zeroForOne) {
            if (amount1Int < 0)
                TransferHelper.safeTransfer(
                    slot0.token1,
                    recipient,
                    uint256(-amount1Int)
                );

            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0Int,
                amount1Int,
                data
            );
            require(balance0Before + uint256(amount0Int) <= balance0(), "IIA");
        } else {
            if (amount0Int < 0)
                TransferHelper.safeTransfer(
                    slot0.token0,
                    recipient,
                    uint256(-amount0Int)
                );

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0Int,
                amount1Int,
                data
            );
            require(balance1Before + uint256(amount1Int) <= balance1(), "IIA");
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0Int,
            amount1Int,
            state.sqrtPriceX96,
            state.liquidity,
            state.tick
        );

        amount0 = uint256(amount0Int > 0 ? amount0Int : -amount0Int);
        amount1 = uint256(amount1Int > 0 ? amount1Int : -amount1Int);
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
        uint160 sqrtPa = TickMath.getSqrtRatioAtTick(self.lowTick);
        uint160 invSqrtPb = TickMath.getSqrtRatioAtTick(-self.highTick);

        address token0 = IUniswapV3Pool(msg.sender).token0();
        address token1 = IUniswapV3Pool(msg.sender).token1();

        VertexId vid0 = newVertexId(token0);
        VertexId vid1 = newVertexId(token1);
        Vertex storage vertex0 = Store.vertex(vid0);
        Vertex storage vertex1 = Store.vertex(vid1);
        uint256 balance0 = VertexImpl.balance(vertex0, vid1);
        uint256 balance1 = VertexImpl.balance(vertex1, vid0);

        // These balances will only take up 128 bits.
        uint256 sqrtXWideX64 = sqrt(
            (((balance0 << 96) + invSqrtPb) << 32) / (self.amplitude + 1)
        );
        uint256 sqrtYWideX64 = sqrt(
            (((balance1 << 96) + sqrtPa) << 32) / (self.amplitude + 1)
        );
        sqrtPriceX96 = uint160((sqrtYWideX64 << 96) / sqrtXWideX64);
        wideLiq = uint128((sqrtYWideX64 * sqrtXWideX64) >> 128);
        narrowLiq = uint128(uint256(wideLiq) * self.amplitude);
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
        Vertex storage vertex0 = Store.vertex(vid0);
        Vertex storage vertex1 = Store.vertex(vid1);
        uint128 balance0 = uint128(VertexImpl.balance(vertex0, vid1));
        uint128 balance1 = uint128(VertexImpl.balance(vertex1, vid0));
        Edge storage edge = Store.edge(token0, token1);
        (narrowLowTick, narrowHighTick) = (edge.lowTick, edge.highTick);
        (sqrtPriceX96, narrowLiq, wideLiq) = edge.getSlot0();
    }

    // Called by the uniEdge when it exchanges one token balance for another.
    function exchange(
        address inToken,
        uint256 inAmount,
        address outToken,
        uint256 outAmount
    ) internal {
        Edge storage edge = Store.edge(inToken, outToken);
        require(
            address(msg.sender) == address(this),
            "Only self can call exchange"
        );

        // We send out the outtoken, and give the intoken to the appropriate closures.
        Vertex storage outVertex = Store.vertex(newVertexId(outToken));
        ClosureDist memory dist = VertexImpl.homSubtract(
            outVertex,
            newVertexId(inToken),
            outAmount
        );

        Vertex storage inVertex = Store.vertex(newVertexId(inToken));
        VertexImpl.homAdd(inVertex, dist, uint128(inAmount));
    }

    function balance0() internal view returns (uint256) {
        Vertex storage vertex = Store.vertex(newVertexId(msg.sender));
        return VertexImpl.balance(vertex, newVertexId(address(this)));
    }

    function balance1() internal view returns (uint256) {
        Vertex storage vertex = Store.vertex(newVertexId(address(this)));
        return VertexImpl.balance(vertex, newVertexId(msg.sender));
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

    /// @notice Calculates the square root of a number
    /// @dev Uses the Babylonian method
    /// @param y The number to calculate the square root of
    /// @return z The square root of y
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
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
        uint160 sqrtPa = TickMath.getSqrtRatioAtTick(low);
        uint160 invSqrtPb = TickMath.getSqrtRatioAtTick(high);
        // See get implied for why this is okay.
        uint256 yWideX128 = (((uint256(balance1) << 96) + sqrtPa) << 32) /
            (amp + 1);
        uint256 xWideX128 = (((uint256(balance0) << 96) + invSqrtPb) << 32) /
            (amp + 1);
        return
            roundUp
                ? FullMath.mulDivRoundingUp(yWideX128, 1 << 128, xWideX128)
                : FullMath.mulDiv(yWideX128, 1 << 128, xWideX128);
    }
}
