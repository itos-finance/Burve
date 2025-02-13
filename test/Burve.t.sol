// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {ForkableTest} from "Commons/Test/ForkableTest.sol";

import {BartioAddresses} from "./utils/BaritoAddresses.sol";
import {Burve, TickRange} from "../src/Burve.sol";
import {IKodiakIsland} from "../src/integrations/kodiak/IKodiakIsland.sol";
import {IUniswapV3Pool} from "../src/integrations/kodiak/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "../src/integrations/uniswap/LiquidityAmounts.sol";
import {TickMath} from "../src/integrations/uniswap/TickMath.sol";

contract BurveTest is ForkableTest {
    Burve public burveV3; // v3 only

    IUniswapV3Pool pool;
    IERC20 token0;
    IERC20 token1;

    function forkSetup() internal virtual override {
        // Pool info
        pool = IUniswapV3Pool(BartioAddresses.KODIAK_HONEY_NECT_POOL_V3);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        int24 tickSpacing = pool.tickSpacing();
        int24 clampedCurrentTick = getClampedCurrentTick();

        // Burve V3
        int24 v3RangeWidth = 10 * tickSpacing;
        TickRange[] memory v3Ranges = new TickRange[](1);
        v3Ranges[0] = TickRange(
            clampedCurrentTick - v3RangeWidth,
            clampedCurrentTick + v3RangeWidth
        );

        uint128[] memory v3Weights = new uint128[](1);
        v3Weights[0] = 1;

        burveV3 = new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            address(0x0),
            v3Ranges,
            v3Weights
        );
    }

    function postSetup() internal override {
        vm.label(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            "HONEY_NECT_POOL_V3"
        );
    }

    function testUniswapV3MintCallback() public {
        uint256 priorPoolBalance0 = token0.balanceOf(address(pool));
        uint256 priorPoolBalance1 = token1.balanceOf(address(pool));

        uint256 amount0Owed = 1e18;
        uint256 amount1Owed = 2e18;

        address alice = makeAddr("Alice");

        // deal tokens to Alice
        deal(address(token0), address(alice), amount0Owed);
        deal(address(token1), address(alice), amount1Owed);

        assertEq(
            token0.balanceOf(alice),
            amount0Owed,
            "alice starting token0 balance"
        );
        assertEq(
            token1.balanceOf(alice),
            amount1Owed,
            "alice starting token0 balance"
        );

        // approve tokens for transfer from Burve
        vm.startPrank(alice);
        token0.approve(address(burveV3), amount0Owed);
        token1.approve(address(burveV3), amount1Owed);
        vm.stopPrank();

        // call uniswapV3MintCallback
        vm.prank(address(pool));
        burveV3.uniswapV3MintCallback(
            amount0Owed,
            amount1Owed,
            abi.encode(alice)
        );

        assertEq(token0.balanceOf(alice), 0, "alice ending token0 balance");
        assertEq(token1.balanceOf(alice), 0, "alice ending token0 balance");

        uint256 postPoolBalance0 = token0.balanceOf(address(pool));
        uint256 postPoolBalance1 = token1.balanceOf(address(pool));

        assertEq(
            postPoolBalance0 - priorPoolBalance0,
            amount0Owed,
            "pool received token0 balance"
        );
        assertEq(
            postPoolBalance1 - priorPoolBalance1,
            amount1Owed,
            "pool received token1 balance"
        );
    }

    function testRevertUniswapV3MintCallbackSenderNotPool() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Burve.UniswapV3MintCallbackSenderNotPool.selector,
                address(this)
            )
        );
        burveV3.uniswapV3MintCallback(0, 0, abi.encode(address(this)));
    }

    // Helpers

    /// @notice Gets the current tick clamped to respect the tick spacing
    function getClampedCurrentTick() internal view returns (int24) {
        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        return currentTick - (currentTick % tickSpacing);
    }

    /**
     * @notice helper function to convert amounts of token0 / token1 to
     * a liquidity value
     * @param sqrtRatioX96 price from slot0
     * @param tickLower bound
     * @param tickUpper bound
     * @param amount0Desired max amount0 available for minting
     * @param amount1Desired max amount1 available for minting
     */
    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal pure returns (uint128 liquidity) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            amount0Desired,
            amount1Desired
        );
    }

    /**
     * @notice helper function to convert the amount of liquidity to
     * amount0 and amount1
     * @param sqrtRatioX96 price from slot0
     * @param tickLower bound
     * @param tickUpper bound
     * @param liquidity to find amounts for
     * @param roundUp round amounts up
     */
    function getAmountsFromLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity,
            roundUp
        );
    }
}
