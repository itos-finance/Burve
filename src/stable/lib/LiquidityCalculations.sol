// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IKodiakIsland} from "../integrations/kodiak/IKodiakIsland.sol";
import {TickMath} from "../integrations/uniswap/TickMath.sol";
import {LiquidityAmounts} from "../integrations/uniswap/LiquidityAmounts.sol";

/// @title Liquidity calculations useful for Burve
library LiquidityCalculations {

    /// @notice Calculates the token and share amounts for an island given the liquidity.
    /// @param island The island 
    /// @param liquidity The liquidity
    /// @return amount0 The amount of token0 in the provided liquidity
    /// @return amount1 The amount of token1 in the provided liquidity
    /// @return shares The amount of island shares that the liquidity represents
    function getAmountsFromIslandLiquidity(
        IKodiakIsland island,
        uint128 liquidity
    ) internal view returns (uint256 amount0, uint256 amount1, uint256 shares) {
        (uint160 sqrtRatioX96, , , , , , ) = island.pool().slot0();

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(island.lowerTick());
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(island.upperTick());

        (uint256 amount0Max, uint256 amount1Max) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity,
            false
        );

        (amount0, amount1, shares) = island.getMintAmounts(
            amount0Max,
            amount1Max
        );
    }
}