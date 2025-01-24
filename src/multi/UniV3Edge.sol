// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "v3-core/contracts/libraries/LowGasSafeMath.sol";
import "v3-core/contracts/libraries/SafeCast.sol";

import "v3-core/contracts/libraries/FullMath.sol";
import "v3-core/contracts/libraries/FixedPoint128.sol";
import "v3-core/contracts/libraries/TransferHelper.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "v3-core/contracts/libraries/SqrtPriceMath.sol";
import "v3-core/contracts/libraries/SwapMath.sol";

import "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import {Edge} from "./Edge.sol";

library UniV3Edge {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /* Helper structs */

    // Typically a compact struct stored in slot 0 for the basic UniV3 implementation.
    // It also holds essential information for swapping.
    // This is co-opted in our setup to simply hold information it needs to fetch from the edge at the start of a swap.
    struct Slot0 {
        // Not in base V3's slot 0, but useful here.
        address token0;
        address token1;
        // the current tick
        int24 tick;
        // the current price
        uint160 sqrtPriceX96;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // The current liquidity. Not normally included in uniswap slot0, but useful here.
        uint128 liquidity;
        /// The pool's fee in hundredths of a bip, i.e. 1e-6
        uint24 fee;
    }

    // the top level state of the swap, the results of which are recorded in storage at the end
    struct SwapState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the current liquidity in range
        uint128 liquidity;
    }

    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    /* Main Func */

    function swap(
        Edge storage edge,
        Slot0 memory slot0Start,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) internal returns (int256 amount0, int256 amount1, uint128 protocolFee) {
        require(amountSpecified != 0, "AS");

        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 &&
                    sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 &&
                    sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            "SPL"
        );

        slot0Start.feeProtocol = zeroForOne
            ? (slot0Start.feeProtocol % 16)
            : (slot0Start.feeProtocol >> 4);

        bool exactInput = amountSpecified > 0;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0Start.sqrtPriceX96,
            tick: slot0Start.tick,
            liquidity: slot0Start.liquidity
        });

        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (
            state.amountSpecifiedRemaining != 0 &&
            state.sqrtPriceX96 != sqrtPriceLimitX96
        ) {
            StepComputations memory step;
            step.sqrtPriceStartX96 = state.sqrtPriceX96;
            step.tickNext = edge.nextTick(state.tick, zeroForOne);

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // get the price for the next tick
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // uint24 fee = FeeFacet(address(this)).getDynamicFee(token0, token1);
            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            (
                state.sqrtPriceX96,
                step.amountIn,
                step.amountOut,
                step.feeAmount
            ) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (
                    zeroForOne
                        ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
                        : step.sqrtPriceNextX96 > sqrtPriceLimitX96
                )
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                slot0Start.fee // TODO: this just becomes the dynamic fee
            );

            if (exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn +
                    step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(
                    step.amountOut.toInt256()
                );
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add(
                    (step.amountIn + step.feeAmount).toInt256()
                );
            }

            // if the protocol fee is on, calculate how much is owed, decrement feeAmount, and increment protocolFee
            if (slot0Start.feeProtocol > 0) {
                uint256 delta = step.feeAmount / slot0Start.feeProtocol;
                step.feeAmount -= delta;
                protocolFee += uint128(delta);
            }

            // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
                state.liquidity = edge.getLiquidity(state.tick); // TODO
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        // No need to update liquidity even if it changed because it's implied by token balances.
        // We don't need fee growth global. The fees earned are returned back to the vertices.

        (amount0, amount1) = zeroForOne == exactInput
            ? (
                amountSpecified - state.amountSpecifiedRemaining,
                state.amountCalculated
            )
            : (
                state.amountCalculated,
                amountSpecified - state.amountSpecifiedRemaining
            );

        // We handle token transfers in Edge.
    }

    /* Private helper methods */

    /// @dev Get this contract's current balance of token0
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance(address token) private view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(
                IERC20Minimal.balanceOf.selector,
                address(this)
            )
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }
}
