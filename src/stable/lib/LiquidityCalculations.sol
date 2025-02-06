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
    /// @return mint0 The amount of token0 in the provided liquidity when minting
    /// @return mint1 The amount of token1 in the provided liquidity when minting
    /// @return mintShares The amount of island shares that the liquidity represents
    function getMintAmountsFromIslandLiquidity(
        IKodiakIsland island,
        uint128 liquidity
    ) internal view returns (uint256 mint0, uint256 mint1, uint256 mintShares) {
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

        (mint0, mint1, mintShares) = island.getMintAmounts(
            amount0Max,
            amount1Max
        );
    }
}