// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
    One HomSet contains all the information needed to handle a swap.
 */

struct HomSet {
    IUniswapV3Pool uniPool;
    // Ticks
    int24 narrowLow;
    int24 narrowHigh;
    // To satisfy price transitivity these ticks must also be transitive.
    // e.g. if narrow low of y/x is -10 then z/y must be 10 in order for z/x to commute.
    uint256 amplitude; // The scaling factor between narrow and wide liquidity. Narrow liq = A * wide liq.
}

using HomSetImpl for HomSet global;

library HomSetImpl {
    function getImplied(
        HomSet storage self,
        uint128 balance0,
        uint128 balance1
    )
        internal
        view
        returns (uint160 sqrtPriceX96, uint128 narrowLiq, uint128 wideLiq)
    {
        // We're actually somewhat restrictive on these token amounts.
        // It's mostly okay because we focus on handling stables and blue chips derivatives.
        // If someone had 2^128 of a stable even with 1e18 decimals, money would be meaningless.
        uint160 sqrtPa = getSqrtRatioAtTick(self.narrowLow);
        uint160 invSqrtPb = getSqrtRatioAtTick(-self.narrowHigh);
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
}
