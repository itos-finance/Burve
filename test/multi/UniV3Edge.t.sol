// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Store} from "../../src/multi/Store.sol";
import {UniV3Edge} from "../../src/multi/UniV3Edge.sol";
import {Edge} from "../../src/multi/Edge.sol";
import {TickMath} from "../../src/multi/uniV3Lib/TickMath.sol";
import {FullMath} from "../../src/multi/FullMath.sol";

contract UniV3EdgeTest is Test {
    uint160 constant SELL_SQRT_LIMIT = TickMath.MIN_SQRT_RATIO + 1;
    uint160 constant BUY_SQRT_LIMIT = TickMath.MAX_SQRT_RATIO - 1;

    Edge public edge;
    uint160 sqrtLowSqrtPriceX96;
    uint160 sqrtInvHighSqrtPriceX96;

    function setUp() public {
        edge.lowTick = int24(-100);
        edge.highTick = int24(100);
        edge.amplitude = uint128(100);
        edge.fee = uint24(0);
        edge.feeProtocol = uint8(0);
        sqrtLowSqrtPriceX96 = TickMath.getSqrtRatioAtTick(-100);
        sqrtInvHighSqrtPriceX96 = TickMath.getSqrtRatioAtTick(-100);
    }

    /* Helpers */

    // Helper for getting what the implied balances should be from a swap.
    function getBalances(
        uint160 sqrtPriceX96,
        uint128 wideLiq,
        uint128 amplitude,
        uint160 lowSqrtPriceX96,
        uint160 invHighSqrtPriceX96
    ) internal pure returns (uint256 x, uint256 y) {
        uint256 xTerm = FullMath.mulDiv(
            uint256(wideLiq) << 96,
            amplitude + 1,
            sqrtPriceX96
        );
        x = xTerm - invHighSqrtPriceX96;
        uint256 yTerm = FullMath.mulX128(
            uint256(sqrtPriceX96) << 32,
            wideLiq * uint256(amplitude + 1),
            false
        );
        y = yTerm - lowSqrtPriceX96;
    }

    function checkedSwap(
        uint160 sqrtPriceX96,
        uint128 wideLiq,
        bool zeroForOne,
        int256 amount
    ) internal view returns (uint160 newSqrtPriceX96) {
        int24 startTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        uint128 startLiq = edge.updateLiquidity(
            startTick,
            edge.highTick,
            wideLiq
        );
        (uint256 startX, uint256 startY) = getBalances(
            sqrtPriceX96,
            startLiq,
            edge.amplitude,
            sqrtLowSqrtPriceX96,
            sqrtInvHighSqrtPriceX96
        );
        UniV3Edge.Slot0 memory slot0 = UniV3Edge.Slot0(
            0, // fee
            0, // feeProtocol
            sqrtPriceX96, // sqrtPriceX96
            startTick, // tick
            startLiq // current liq
        );
        (
            int256 x,
            int256 y,
            ,
            uint160 finalSqrtPriceX96,
            int24 finalTick
        ) = UniV3Edge.swap(
                edge,
                slot0,
                zeroForOne,
                amount,
                zeroForOne ? SELL_SQRT_LIMIT : BUY_SQRT_LIMIT
            );
        uint128 finalLiq = edge.updateLiquidity(finalTick, startTick, startLiq);
        (uint256 finalX, uint256 finalY) = getBalances(
            finalSqrtPriceX96,
            finalLiq,
            edge.amplitude,
            sqrtLowSqrtPriceX96,
            sqrtInvHighSqrtPriceX96
        );
        if (x > 0) {
            assertEq(finalX - startX, uint256(x));
        } else {
            assertEq(startX - finalX, uint256(-x));
        }

        if (y > 0) {
            assertEq(finalY - startY, uint256(y));
        } else {
            assertEq(startY - finalY, uint256(-y));
        }
        newSqrtPriceX96 = finalSqrtPriceX96;
    }

    /* Test */

    function testSwap() public {
        uint160 startSqrtPriceX96 = 1 << 96;
        int24 startTick = 0;
        UniV3Edge.Slot0 memory slot0 = UniV3Edge.Slot0(
            0, // fee
            0, // feeProtocol
            startSqrtPriceX96, // sqrtPriceX96
            startTick, // tick
            1000e18 // current liq
        );

        (
            int256 x,
            int256 y,
            uint128 proto,
            uint160 finalSqrtPriceX96,
            int24 finalTick
        ) = UniV3Edge.swap(edge, slot0, true, 100e18, SELL_SQRT_LIMIT);
        // Generally correct values.
        assertEq(proto, 0);
        assertLt(y, 0);
        assertGt(x, 0);

        // Try again but what if the liquidity was more concentrated.
        edge.lowTick = int24(-10);
        edge.highTick = int24(10);
        (int256 x10, int256 y10, , , ) = UniV3Edge.swap(
            edge,
            slot0,
            true,
            100e18,
            SELL_SQRT_LIMIT
        );
        assertEq(x, x10);
        assertGt(y10, y);
    }

    function testSwap2() public {
        UniV3Edge.Slot0 memory slot0 = UniV3Edge.Slot0(
            0, // fee
            0, // feeProtocol
            1 << 96, // sqrtPriceX96
            0, // tick
            1000e18 // current liq
        );

        UniV3Edge.swap(edge, slot0, true, 100e18, SELL_SQRT_LIMIT);
    }
}
