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
import {SafeCast} from "Commons/Math/Cast.sol";

// We have our own limit on what the price can be and reject any attempt to swap beyond that.
// This is because we're specifically designed for pegged assets, and at once point
// we don't want to accept more impermanent loss (which will be quite permament if its a true depeg).
// If it is not a true depeg, we still allow users to buy/sell the price back to the peg.
// Essentially, we're saying that the market making fees when outside of these price ranges is not worth
// the depeg risk for what should be pegged assets.
// We restrict prices to be between 1e6 and 1e-6. Conveniently fits in 20 bits.
uint128 constant MIN_SQRT_PRICE_X96 = uint128(1 << 96) / 1000;
uint128 constant MAX_SQRT_PRICE_X96 = uint128(1000 << 96);
uint16 constant MAX_AMP = 4000; // 4000 would be very excessive. Too much stability.
// By restricting to these constants, amplitude * price will always fit in Q32X96.
// This let's us compute much more efficiently.
// NOTE: We force all tokens 18 decimals to stay within this price range. We wrap
// any non-compliant tokens with a thin 18 decimal wrapper.
int24 constant MAX_NARROW_TICK = 46064; // Exclusive
int24 constant MIN_NARROW_TICK = -MAX_NARROW_TICK; // Inclusive

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
    /* Cached values infered from ticks that saves us implied compute */
    uint160 lowSqrtPriceX96; // sqrt(Pa) for the narrow range.
    uint160 highSqrtPriceX96; // sqrt(Pb) for the narrow range.
    uint160 invLowSqrtPriceX96; // 1/sqrt(Pa) for the narrow range.
    uint160 invHighSqrtPriceX96; // 1/sqrt(Pb) for the narrow range.
    uint256 xyBoundX128; // If x/y is greater than this, then P < Pa.
    uint256 yxBoundX128; // If y/x is greater than this, then P >= Pb.
}

using EdgeImpl for Edge global;

library EdgeImpl {
    uint256 constant X224 = 1 << 224; // used in getInvPriceX128

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
    error SwapOutOfBounds(uint160 newSqrtPriceX96);

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
        require(lowTick >= MIN_NARROW_TICK, "ERL");
        self.highTick = highTick;
        require(highTick < MAX_NARROW_TICK, "ERH");
        self.amplitude = amplitude; // Liq in narrow range is (amplitude + 1) * wideLiq
        require(amplitude < MAX_AMP, "ERA");
        /* compute cache values */
        self.lowSqrtPriceX96 = TickMath.getSqrtRatioAtTick(lowTick);
        self.highSqrtPriceX96 = TickMath.getSqrtRatioAtTick(highTick);
        self.invLowSqrtPriceX96 = TickMath.getSqrtRatioAtTick(-lowTick);
        self.invHighSqrtPriceX96 = TickMath.getSqrtRatioAtTick(-highTick);
        uint160 invDelta = self.invLowSqrtPriceX96 - self.invHighSqrtPriceX96;
        uint160 delta = self.highSqrtPriceX96 - self.lowSqrtPriceX96;
        self.xyBoundX128 = calcLowerBoundRatio(
            amplitude,
            self.invLowSqrtPriceX96,
            invDelta
        );
        self.yxBoundX128 = calcUpperBoundRatio(
            amplitude,
            self.highSqrtPriceX96,
            delta
        );
    }

    function setFee(Edge storage self, uint24 fee, uint8 feeProtocol) internal {
        self.fee = fee;
        self.feeProtocol = feeProtocol;
    }

    /* Interface functions */

    /// A complete swap function that calculates and exchanges one token for another.
    /// @dev This does NOT modify edge.
    /// @param token0 The lower address token.
    function swap(
        Edge storage self,
        address token0,
        address token1,
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) internal returns (uint256 inAmount, uint256 outAmount) {
        // Log the start of the swap function
        // Prep the swap.
        UniV3Edge.Slot0 memory slot0 = getSlot0(
            self,
            token0,
            token1,
            !zeroForOne
        );

        // Calculate the swap amounts and protocolFee
        (
            int256 amount0,
            int256 amount1,
            uint128 protocolFee,
            uint160 finalSqrtPriceX96,
            int24 finalTick
        ) = UniV3Edge.swap(
                self,
                slot0,
                zeroForOne,
                amountSpecified,
                sqrtPriceLimitX96
            );
        if (
            (zeroForOne && (finalSqrtPriceX96 < MIN_SQRT_PRICE_X96)) ||
            (!zeroForOne && (finalSqrtPriceX96 > MAX_SQRT_PRICE_X96))
        ) revert SwapOutOfBounds(finalSqrtPriceX96);
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

        uint128 finalLiq = updateLiquidity(
            self,
            finalTick,
            slot0.tick,
            slot0.liquidity
        );

        emit Swap(
            msg.sender,
            recipient,
            token0,
            token1,
            amount0,
            amount1,
            finalSqrtPriceX96,
            finalLiq,
            finalTick
        );
    }

    /* Methods used by the UniV3Edge */

    /// Called by the UniV3Edge to fetch the information it needs to swap.
    /// @param roundUp Whether we want to round the price up or down.
    function getSlot0(
        Edge storage self,
        address token0,
        address token1,
        bool roundUp
    ) internal view returns (UniV3Edge.Slot0 memory slot0) {
        slot0.fee = self.fee;
        slot0.feeProtocol = self.feeProtocol;
        (slot0.sqrtPriceX96, slot0.tick, slot0.liquidity) = calcImpliedPool(
            self,
            token0,
            token1,
            roundUp
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
        if (startIn) return nowIn ? startLiq : startLiq / (self.amplitude + 1);
        else return nowIn ? startLiq * (self.amplitude + 1) : startLiq;
    }

    /* Private Swap Helpers */

    // Called to perform the actual exchange from one token balance to another.
    function exchange(
        address recipient,
        address inToken,
        uint256 inAmount,
        address outToken,
        uint256 outAmount,
        uint256 protocolFee
    ) private {
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
    /// @dev Round the price up when buying, round down when selling. Always round liq down.
    function calcImpliedPool(
        Edge storage self,
        address token0,
        address token1,
        bool roundUp
    )
        internal
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint128 currentLiq)
    {
        VertexId v0 = newVertexId(token0);
        VertexId v1 = newVertexId(token1);
        // Rounding down both balances will round down liq.
        // It has de minimus effects on price.
        // We assume the balances are within 128 bits and we don't own the worlds economy
        // because we force all tokens to 18 decimals and only put pegged assets together.
        uint128 balance0 = SafeCast.toUint128(
            Store.vertex(v0).balance(v1, false)
        );
        uint128 balance1 = SafeCast.toUint128(
            Store.vertex(v1).balance(v0, false)
        );
        (sqrtPriceX96, currentLiq) = calcImpliedInner(
            self,
            balance0,
            balance1,
            roundUp
        );
        // So far, currentLiq is actually wideLiq.
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        if (self.lowTick <= tick && tick < self.highTick)
            currentLiq += uint128(self.amplitude * currentLiq);
    }

    function calcImpliedInner(
        Edge storage self,
        uint256 balance0,
        uint256 balance1,
        bool roundUp
    ) private view returns (uint160 sqrtPriceX96, uint128 wideLiq) {
        // If we're rounding the price up we want to round x/y down to stay out of the bottom region.
        // But that means rounding up here in this form of the comparison.
        // And conveniently vice versa when rounding down, we round x/y up, so we round the mult down.
        uint256 xBound = FullMath.mulX128(self.xyBoundX128, balance1, roundUp);
        if (balance0 > xBound)
            (sqrtPriceX96, wideLiq) = calcLowerImplied(
                self,
                balance0,
                balance1,
                roundUp
            );
        else {
            uint256 yBound = FullMath.mulX128(
                self.yxBoundX128,
                balance0,
                !roundUp
            );
            if (balance1 > yBound)
                (sqrtPriceX96, wideLiq) = calcUpperImplied(
                    self,
                    balance0,
                    balance1,
                    roundUp
                );
            else
                (sqrtPriceX96, wideLiq) = calcInnerImplied(
                    self,
                    balance0,
                    balance1,
                    roundUp
                );
        }
    }

    /* Math methods for calculating the implied uniV3 pool state */

    /// This calculates the ratio of x to y such that if the actual ratio is greater
    /// than this, then the implied price is below P_a.
    function calcLowerBoundRatio(
        uint128 amp,
        uint160 invSqrtLowX96,
        uint256 invDeltaX96
    ) private pure returns (uint256 xyBoundX128) {
        uint256 inner = invSqrtLowX96 + amp * invDeltaX96;
        // We round the bounds down so its a little easier to be in out of the concentrated range.
        // The only downside is that potentially we go back to the peg slightly easier by 1 token.
        // If we need to, we can make a rounded up bound and a rounded down bound.
        xyBoundX128 = FullMath.mulX128(
            inner,
            uint256(invSqrtLowX96) << 64,
            false
        );
    }

    /// Calculate the ratio of y over x such that if the actual ratio is greater than or equal to this,
    /// then the implied price is equal to or above P_b.
    function calcUpperBoundRatio(
        uint128 amp,
        uint160 sqrtHighX96,
        uint256 deltaX96
    ) private pure returns (uint256 yxBoundX128) {
        uint256 inner = sqrtHighX96 + amp * deltaX96;
        // We round the bounds down so its a little easier to be in out of the concentrated range.
        // The only downside is that potentially we go back to the peg slightly easier by 1 token.
        // If we need to, we can make a rounded up bound and a rounded down bound.
        yxBoundX128 = FullMath.mulX128(
            inner,
            uint256(sqrtHighX96) << 64,
            false
        );
    }

    /// Compute the implied pool when we know the price is below the narrow range's low tick.
    /// @param x balance0 - 128 bits
    /// @param y balance1 - 128 bits
    function calcLowerImplied(
        Edge storage self,
        uint256 x,
        uint256 y,
        bool roundUp
    ) private view returns (uint160 sqrtPriceX96, uint128 wideLiq) {
        // Due to our constraints this is smaller than 26 non-fractional bits.
        // We can't go straight to X192 because we DON'T know if that will fit, but
        // X128 is more than enough precision. The other 64 is to match b^2.
        uint256 xyX192 = ((x << 128) / y) << 64;
        // Due to our constaints, this only has at most 16 = 4 + 12 positive bits.
        uint256 bX96 = self.amplitude *
            uint256(self.invLowSqrtPriceX96 - self.invHighSqrtPriceX96);
        // By our constraints we know bX96^2 is in 244 bits so the sum is okay.
        // After the sqrt and sum, it takes up less than 114 bits so we can multiply by y.
        uint256 numX96 = (bX96 + sqrt(bX96 * bX96 + 4 * xyX192)) * y;
        uint256 denom = 2 * x;
        sqrtPriceX96 = uint160(numX96 / denom);
        wideLiq = uint128((y << 96) / sqrtPriceX96); // Liq is never rounded up
        if (roundUp && (numX96 % denom > 0)) sqrtPriceX96 += 1;
    }

    /// Compute the implied pool when we know the price is above the narrow range's low tick.
    /// @param x balance0 - 128 bits
    /// @param y balance1 - 128 bits
    function calcUpperImplied(
        Edge storage self,
        uint256 x,
        uint256 y,
        bool roundUp
    ) private view returns (uint160 sqrtPriceX96, uint128 wideLiq) {
        // Due to our constraints this is smaller than 26 non-fractional bits.
        // We can't go straight to X192 because we DON'T know if that will fit, but
        // X128 is more than enough precision. The other 64 is to match b^2.
        uint256 yxX192 = ((y << 128) / x) << 64;
        // Due to our constaints, this only has at most 16 = 4 + 12 positive bits.
        uint256 bX96 = self.amplitude *
            uint256(self.highSqrtPriceX96 - self.lowSqrtPriceX96);
        // By our constraints we know bX96^2 is in 244 bits so the sum is okay.
        // After the sqrt and sum, this takes up less than 114 bits.
        uint256 numX96 = sqrt(bX96 * bX96 + 4 * yxX192) - bX96;
        uint256 isOdd = numX96 & 0x1;
        sqrtPriceX96 = uint160(numX96 / 2);
        wideLiq = uint128((x * sqrtPriceX96) >> 96); // Fits without FullMath!
        if (roundUp && (isOdd > 0)) sqrtPriceX96 += 1;
    }

    /// Compute the implied pool when we know the price is within the narrow range's ticks.
    /// @param x balance0 - 128 bits
    /// @param y balance1 - 128 bits
    function calcInnerImplied(
        Edge storage self,
        uint256 x,
        uint256 y,
        bool roundUp
    ) private view returns (uint160 sqrtPriceX96, uint128 wideLiq) {
        uint256 b1X96 = self.lowSqrtPriceX96;
        uint256 b2X96 = roundUp
            ? FullMath.mulDivRoundingUp(y, self.invHighSqrtPriceX96, x)
            : FullMath.mulDiv(y, self.invHighSqrtPriceX96, x);
        uint256 yxX192 = ((y << 128) / x) << 64;
        uint256 amp1 = self.amplitude + 1;
        uint256 numX96;
        if (b1X96 > b2X96) {
            uint256 bX96 = (b1X96 - b2X96) * self.amplitude;
            numX96 = sqrt(bX96 * bX96 + 4 * yxX192 * amp1 * amp1) + bX96;
        } else {
            uint256 bX96 = (b2X96 - b1X96) * self.amplitude;
            numX96 = sqrt(bX96 * bX96 + 4 * yxX192 * amp1 * amp1) - bX96;
        }
        uint256 denom = 2 * amp1;
        sqrtPriceX96 = uint160(numX96 / denom);
        wideLiq = uint128(
            (y << 96) /
                (amp1 * sqrtPriceX96 - self.amplitude * self.lowSqrtPriceX96)
        );
        if (roundUp && (numX96 % denom > 0)) sqrtPriceX96 += 1;
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
        (uint256 sqrtPriceX96, ) = calcImpliedInner(
            self,
            balance0,
            balance1,
            true
        );

        return FullMath.mulX128(sqrtPriceX96, sqrtPriceX96 << 64, true);
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
        (uint256 sqrtPriceX96, ) = calcImpliedInner(
            self,
            balance0,
            balance1,
            false // Round down to round inv up.
        );
        uint256 invSqrtX128 = X224 / sqrtPriceX96;
        if (X224 % sqrtPriceX96 > 0) invSqrtX128 += 1;
        return FullMath.mulX128(invSqrtX128, invSqrtX128, true);
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
}
