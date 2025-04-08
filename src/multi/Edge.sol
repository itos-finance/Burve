// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {VertexId} from "./vertex/Vertex.sol";

/*
    Facilitates all swaps.
 */
struct Edge {
    /* Swap info */
    uint256 baseFeeX128; // The flat fee we charge on all swaps.
    // These control the slippage inherent in a swap.
    mapping(VertexId => ValueCurve) curves;
}

// Our fee structure is a bonding curve described by
// ((scale + 1) * target_value) ^ (2^pow) / ((n - 1) * (x + scale * target_value)^(2^pow - 1))
// where x is the balance of the given token, and changes in the output of this equation
// is the change in the value of the deposited token balance.
struct ValueCurve {
    uint128 scale;
    uint8 pow2;
}

using ValueCurveImpl for ValueCurve global;

library ValueCurveImpl

using EdgeImpl for Edge global;

library EdgeImpl {
    uint256 constant X224 = 1 << 224; // used in getInvPriceX128

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

    /* Price functions used by LiqFacet */

    /// Fetch the REAL price implied by these balances on this edge denoted in terms of token1.
    /// @dev This ALWAYS rounds up due to its usage in Add.
    /// @param balance0 This is the balance of token0
    /// @param balance1 This is the balance of token1
    /// @return priceX128 This is the price denoted with token1 as the numeraire.
    function getPriceX128(
        Edge storage self,
        uint128 balance0,
        uint128 balance1
    ) internal view returns (uint256 priceX128) {
        (uint256 sqrtPriceX96, ) = calcImpliedHelper(
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
        (uint256 sqrtPriceX96, ) = calcImpliedHelper(
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
