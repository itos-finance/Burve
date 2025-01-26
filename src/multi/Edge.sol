// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TickMath} from "./uniV3Lib/TickMath.sol";
import {UniV3Edge} from "./UniV3Edge.sol";
import {FullMath} from "./FullMath.sol";
import {Store} from "./Store.sol";
import {SimplexStorage} from "./facets/SimplexFacet.sol";
import {TransferHelper} from "../TransferHelper.sol";
import {VertexId, newVertexId} from "./Vertex.sol";
import {ClosureDist} from "./Closure.sol";

/*
    Contains all information relation to the pool used to swap between two vertices.
 */

struct Edge {
    /* Swap info */
    // TODO in the future we may make this a list of amplitudes and ticks.
    // For now we just use one range.
    int24 lowTick;
    int24 highTick;
    // To satisfy price transitivity these ticks must also be transitive.
    // e.g. if narrow low of y/x is -10 then z/y must be 10 in order for z/x to commute.
    uint128 amplitude; // The scaling factor between narrow and wide liquidity. Narrow liq = A * wide liq.
    /* Other slot0 info */
    uint24 fee; // Fee rate for swaps
    uint8 feeProtocol; // Fee rate for the protocol
}

using EdgeImpl for Edge global;

library EdgeImpl {
    event Swap(
        address sender,
        address recipient,
        address token0,
        address token1,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    error NoEdgeSettings(address token0, address token1);

    /* Admin function to set edge parameters */

    /// @dev This is simple because we recalculate the implied price every time.
    /// Just be sure to set the ticks such that the price diagram commutes.
    function setRange(
        Edge storage self,
        uint128 amplitude,
        int24 lowTick,
        int24 highTick
    ) internal {
        self.lowTick = lowTick;
        self.highTick = highTick;
        self.amplitude = amplitude;
    }

    function setFee(Edge storage self, uint24 fee, uint8 feeProtocol) internal {
        self.fee = fee;
        self.feeProtocol = feeProtocol;
    }

    // The main function to support.
    // @param token0 The lower address token.
    function swap(
        Edge storage self,
        address token0,
        address token1,
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) internal returns (uint256 inAmount, uint256 outAmount) {
        // Prep the swap.
        UniV3Edge.Slot0 memory slot0 = getSlot0(self, token0, token1);

        // Calculate the swap amounts and protocolFee
        (int256 amount0, int256 amount1, uint128 protocolFee) = UniV3Edge.swap(
            self,
            slot0,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96
        );

        address inToken;
        address outToken;
        if (zeroForOne) {
            inToken = token0;
            inAmount = uint256(amount0);
            outToken = token1;
            outAmount = uint256(-amount1);
        } else {
            inToken = token1;
            inAmount = uint256(amount1);
            outToken = token0;
            outAmount = uint256(-amount0);
        }
        exchange(
            recipient,
            inToken,
            inAmount,
            outToken,
            outAmount,
            protocolFee
        );

        (uint160 sqrtPriceX96, int24 tick, uint128 liquidity) = calcImpliedPool(
            self,
            token0,
            token1
        );
        emit Swap(
            msg.sender,
            recipient,
            token0,
            token1,
            amount0,
            amount1,
            sqrtPriceX96,
            liquidity,
            tick
        );
    }

    /* Methods used by the UniV3Edge */

    /// Called by the UniV3Edge to fetch the information it needs to swap.
    function getSlot0(
        Edge storage self,
        address token0,
        address token1
    ) private view returns (UniV3Edge.Slot0 memory slot0) {
        // If this edge has never been called before we will set ourselves to the default edge
        if (self.amplitude == 0) {
            self = Store.simplex().defaultEdge;
            if (self.amplitude == 0) revert NoEdgeSettings(token0, token1);
        }
        slot0.fee = self.fee;
        slot0.feeProtocol = self.feeProtocol;
        (slot0.sqrtPriceX96, slot0.tick, slot0.liquidity) = calcImpliedPool(
            self,
            token0,
            token1
        );
    }

    /// Fetch the next tick in either direction
    function nextTick(
        Edge storage self,
        int24 currentTick,
        bool isSell /* same as zeroForOne */
    ) internal view returns (int24) {
        if (isSell) {
            // When selling, even if we're at the next tick,
            // we still return the same tick because the swap will move to tick - 1.
            if (currentTick >= self.highTick) return self.highTick;
            else if (currentTick >= self.lowTick) return self.lowTick;
            else return (TickMath.MIN_TICK);
        } else {
            if (currentTick < self.lowTick) return self.lowTick;
            else if (currentTick < self.highTick) return self.highTick;
            else return (TickMath.MAX_TICK);
        }
    }

    /// Update the liquidity from one tick to another.
    function updateLiquidity(
        Edge storage self,
        int24 currentTick,
        int24 startTick,
        uint128 startLiq
    ) internal view returns (uint128 currentLiq) {
        bool startIn = (self.lowTick <= startTick && startTick < self.highTick);
        bool nowIn = (self.lowTick <= currentTick &&
            currentTick < self.highTick);
        if (startIn) return nowIn ? startLiq : startLiq / self.amplitude;
        else return nowIn ? startLiq * self.amplitude : startLiq;
    }

    /* Swap Helpers */

    // Called to perform the actual exchange from one token balance to another.
    function exchange(
        address recipient,
        address inToken,
        uint256 inAmount,
        address outToken,
        uint256 outAmount,
        uint256 protocolFee
    ) internal {
        VertexId inVid = newVertexId(inToken);
        VertexId outVid = newVertexId(outToken);
        // We send out the outtoken, and give the intoken to the appropriate closures.
        ClosureDist memory dist = Store.vertex(outVid).homSubtract(
            inVid,
            outAmount
        );
        if (outAmount > 0)
            TransferHelper.safeTransfer(outToken, recipient, outAmount);
        if (inAmount > 0)
            TransferHelper.safeTransferFrom(
                inToken,
                msg.sender,
                address(this),
                inAmount
            );
        // We leave the protocolFee on this contract.
        Store.vertex(inVid).homAdd(dist, inAmount - protocolFee);
    }

    /// Fetch the price, tick, and liquidity implied by the current balances for these tokens.
    function calcImpliedPool(
        Edge storage self,
        address token0,
        address token1
    )
        private
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint128 currentLiq)
    {
        VertexId v0 = newVertexId(token0);
        VertexId v1 = newVertexId(token1);
        uint256 balance0 = Store.vertex(v0).balance(v1, false);
        uint256 balance1 = Store.vertex(v1).balance(v0, false);
        (sqrtPriceX96, currentLiq) = calcAmounts(self, balance0, balance1);
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        if (self.lowTick <= tick && tick < self.highTick)
            currentLiq = uint128(self.amplitude * currentLiq);
    }

    function calcAmounts(
        Edge storage self,
        uint256 balance0,
        uint256 balance1
    ) private view returns (uint160 sqrtPriceX96, uint128 wideLiq) {
        // We're actually somewhat restrictive on these token amounts.
        // It's mostly okay because we focus on handling stables and blue chips derivatives.
        // If someone actually had 2^128 of a stable, even with 1e18 decimals, all money would be worthless.
        uint160 sqrtPa = TickMath.getSqrtRatioAtTick(self.lowTick);
        uint160 invSqrtPb = TickMath.getSqrtRatioAtTick(-self.highTick);
        // These balances will only take up 128 bits.
        uint256 sqrtXWideX64 = sqrt(
            (((uint256(balance0) << 96) + invSqrtPb) << 32) /
                (self.amplitude + 1)
        );
        uint256 sqrtYWideX64 = sqrt(
            (((uint256(balance1) << 96) + sqrtPa) << 32) / (self.amplitude + 1)
        );
        // Given the codomain, these casts are safe.
        sqrtPriceX96 = uint160((sqrtYWideX64 << 96) / sqrtXWideX64);
        wideLiq = uint128((sqrtYWideX64 * sqrtXWideX64) >> 128);
    }

    /* Helper Price functions */

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

    function sqrt(uint x) private pure returns (uint y) {
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
