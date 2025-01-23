// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {FullMath} from "./FullMath.sol";

/**
    Contains all information relation to the pool used to swap between two vertices.
 */

struct Edge {
    // TODO in the future we may make this a list of amplitudes and ticks.
    // For now we just use one range.
    int24 lowTick;
    int24 highTick;
    // To satisfy price transitivity these ticks must also be transitive.
    // e.g. if narrow low of y/x is -10 then z/y must be 10 in order for z/x to commute.
    uint256 amplitude; // The scaling factor between narrow and wide liquidity. Narrow liq = A * wide liq.
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

    /// Called by the UniV3Edge to fetch the information it needs to swap.
    function getSlot0(
        Edge storage self,
        uint128 balance0,
        uint128 balance1
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
