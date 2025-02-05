// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Burve, TickRange, TickRangeImpl} from "../../src/stable/Burve.sol";
import {BartioAddresses} from "./../utils/BaritoAddresses.sol";
import {IKodiakIsland} from "../../src/stable/integrations/kodiak/IKodiakIsland.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiquidityAmounts} from "../../src/stable/integrations/uniswap/LiquidityAmounts.sol";
import {TickMath} from "../../src/stable/integrations/uniswap/TickMath.sol";
import {IUniswapV3Pool} from "../../src/stable/integrations/kodiak/IUniswapV3Pool.sol";
import {ForkableTest} from "@Commons/Test/ForkableTest.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {TransferHelper} from "./../../src/TransferHelper.sol";

contract BurveTest is ForkableTest {
    Burve public burveV3;
    Burve public burveIsland;

    function forkSetup() internal virtual override {
        IUniswapV3Pool uniPool = IUniswapV3Pool(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3
        );
        (, int24 currentTick, , , , , ) = uniPool.slot0();
        int24 tickSpacing = uniPool.tickSpacing();
        int24 clampedCurrentTick = currentTick - (currentTick % tickSpacing);

        int24 rangeWidth = 100;
        TickRange[] memory ranges = new TickRange[](2);
        uint128[] memory weights = new uint128[](2);

        // Burve Island
        TickRange[] memory islandRanges = new TickRange[](1);
        islandRanges[0] = TickRange(0, 0);

        uint128[] memory islandWeights = new uint128[](1);
        islandWeights[0] = 1;

        burveIsland = new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            BartioAddresses.KODIAK_HONEY_NECT_ISLAND,
            islandRanges,
            islandWeights
        );

        // Burve V3

        rangeWidth = 10 * tickSpacing;
        ranges[0] = TickRange(
            clampedCurrentTick - rangeWidth,
            clampedCurrentTick + rangeWidth
        );
        rangeWidth = 100 * tickSpacing;
        ranges[1] = TickRange(
            clampedCurrentTick - rangeWidth,
            clampedCurrentTick + rangeWidth
        );

        weights[0] = 3;
        weights[1] = 1;

        burveV3 = new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            address(0x0),
            ranges,
            weights
        );
    }

    function postSetup() internal override {
        vm.label(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            "HONEY_NECT_POOL_V3"
        );
        vm.label(BartioAddresses.KODIAK_HONEY_NECT_ISLAND, "HONEY_NECT_ISLAND");
    }

    // Tests
    // - constructor
    // - mint
    // - burn
    // - getInfo

    // Contructor Tests

    function testV3Setup() public forkOnly {
        IUniswapV3Pool uniPool = IUniswapV3Pool(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3
        );
        (, int24 currentTick, , , , , ) = uniPool.slot0();
        int24 tickSpacing = uniPool.tickSpacing();

        assertEq(address(burveV3.pool()), address(uniPool), "pool address");
        assertEq(address(burveV3.token0()), uniPool.token0(), "token0 address");
        assertEq(address(burveV3.token1()), uniPool.token1(), "token1 address");

        assertEq(address(burveV3.island()), address(0x0), "island address");

        (int24 lower, int24 upper) = burveV3.ranges(0);
        assertEq(lower, currentTick - 10 * tickSpacing, "range 0 lower");
        assertEq(upper, currentTick + 10 * tickSpacing, "range 0 upper");
        (lower, upper) = burveV3.ranges(1);
        assertEq(lower, currentTick - 100 * tickSpacing, "range 1 lower");
        assertEq(upper, currentTick + 100 * tickSpacing, "range 1 upper");

        assertEq(
            burveV3.distX96(0),
            59421121885698253195157962752,
            "distX96 0"
        ); // 3/4
        assertEq(
            burveV3.distX96(1),
            19807040628566084398385987584,
            "distX96 1"
        ); // 1/4
    }

    // Mint Tests

    function testV3Mint() public {
        IUniswapV3Pool uniPool = IUniswapV3Pool(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3
        );

        address user = address(0xabc);

        deal(uniPool.token0(), address(user), 10_000e18);
        deal(uniPool.token1(), address(user), 10_000e18);

        vm.startPrank(user);

        IERC20(uniPool.token0()).approve(address(burveV3), 10_000e18);
        IERC20(uniPool.token1()).approve(address(burveV3), 10_000e18);

        burveV3.mint(address(user), 1000);

        vm.stopPrank();
    }

    function testIslandMint() public {
        IUniswapV3Pool uniPool = IUniswapV3Pool(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3
        );

        address user = address(0xabc);

        deal(uniPool.token0(), address(user), 10_000e18);
        deal(uniPool.token1(), address(user), 10_000e18);

        // deal(uniPool.token0(), address(burveIsland), 10_000e18);
        // deal(uniPool.token1(), address(burveIsland), 10_000e18);

        // vm.startPrank(address(burveIsland));
        // IERC20(uniPool.token0()).approve(
        //     BartioAddresses.KODIAK_HONEY_NECT_ISLAND,
        //     10_000e18
        // );
        // IERC20(uniPool.token1()).approve(
        //     BartioAddresses.KODIAK_HONEY_NECT_ISLAND,
        //     10_000e18
        // );
        // vm.stopPrank();

        vm.startPrank(user);

        IERC20(uniPool.token0()).approve(address(burveIsland), 10_000e18);
        IERC20(uniPool.token1()).approve(address(burveIsland), 10_000e18);

        burveIsland.mint(address(user), 1000);

        vm.stopPrank();
    }

    function testAThing() public {}

    // function testCalcLiq() public {
    //     address poolAddr = 0x246c12D7F176B93e32015015dAB8329977de981B;
    //     IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);

    //     console.log("tick spacing: ", pool.tickSpacing());

    //     uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(-139);
    //     uint160 lowerSqrtP = TickMath.getSqrtRatioAtTick(-1000);
    //     uint160 upperSqrtP = TickMath.getSqrtRatioAtTick(800);
    //     console.log("lower sqrt: ", upperSqrtP);
    //     console.log("upper sqrt: ", lowerSqrtP);

    //     (uint256 amount0, uint256 amount1) = LiquidityAmounts
    //         .getAmountsForLiquidity(sqrtRatioX96, lowerSqrtP, upperSqrtP, 1000);
    //     console.log("amount0: ", amount0);
    //     console.log("amount1: ", amount1);
    // }

    // function testStableMint() public {
    //     address burveAddr = 0xda5826868528Ace919721ef324a69c16b9486D08;
    //     address me = address(0x0); // replace with your address

    //     burve = Burve(burveAddr);

    //     IERC20(burve.token0()).approve(burveAddr, 1000);
    //     IERC20(burve.token1()).approve(burveAddr, 1000);

    //     burve.mint(me, 1000);
    // }

    // function testIsland() public {
    //     address me = address(0x0); // replace with your address
    //     vm.startPrank(me);

    //     IKodiakIsland island = IKodiakIsland(
    //         BartioAddresses.KODIAK_BERA_YEET_ISLAND_NEW
    //     );

    //     // TODO(Austin): Not working? Improper setup?
    //     uint256 balance0 = island.token0().balanceOf(me);
    //     uint256 balance1 = island.token1().balanceOf(me);

    //     (uint160 sqrtRatioX96, , , , , , ) = island.pool().slot0();

    //     uint128 calcLiq = getLiquidityForAmounts(
    //         sqrtRatioX96,
    //         island.lowerTick(),
    //         island.upperTick(),
    //         balance0,
    //         balance1
    //     );

    //     (uint256 mint0, uint256 mint1) = getAmountsFromLiquidity(
    //         sqrtRatioX96,
    //         island.lowerTick(),
    //         island.upperTick(),
    //         calcLiq,
    //         false
    //     );

    //     (uint256 transfer0, uint256 transfer1, uint256 mintedAmount) = island
    //         .getMintAmounts(balance0, balance1);
    //     assert(transfer0 <= balance0);
    //     assert(transfer1 <= balance1);

    //     island.token0().approve(address(island), transfer0);
    //     island.token1().approve(address(island), transfer1);

    //     (, , uint128 liqMinted) = island.mint(mintedAmount, me);

    //     assertEq(liqMinted, calcLiq);

    //     vm.stopPrank();
    // }

    // /**
    //  * @notice helper function to convert amounts of token0 / token1 to
    //  * a liquidity value
    //  * @param sqrtRatioX96 price from slot0
    //  * @param tickLower bound
    //  * @param tickUpper bound
    //  * @param amount0Desired max amount0 available for minting
    //  * @param amount1Desired max amount1 available for minting
    //  */
    // function getLiquidityForAmounts(
    //     uint160 sqrtRatioX96,
    //     int24 tickLower,
    //     int24 tickUpper,
    //     uint256 amount0Desired,
    //     uint256 amount1Desired
    // ) internal pure returns (uint128 liquidity) {
    //     uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
    //     uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    //     liquidity = LiquidityAmounts.getLiquidityForAmounts(
    //         sqrtRatioX96,
    //         sqrtRatioAX96,
    //         sqrtRatioBX96,
    //         amount0Desired,
    //         amount1Desired
    //     );
    // }

    // /**
    //  * @notice helper function to convert the amount of liquidity to
    //  * amount0 and amount1
    //  * @param sqrtRatioX96 price from slot0
    //  * @param tickLower bound
    //  * @param tickUpper bound
    //  * @param liquidity to find amounts for
    //  * @param roundUp round amounts up
    //  */
    // function getAmountsFromLiquidity(
    //     uint160 sqrtRatioX96,
    //     int24 tickLower,
    //     int24 tickUpper,
    //     uint128 liquidity,
    //     bool roundUp
    // ) internal pure returns (uint256 amount0, uint256 amount1) {
    //     uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
    //     uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    //     (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
    //         sqrtRatioX96,
    //         sqrtRatioAX96,
    //         sqrtRatioBX96,
    //         liquidity,
    //         roundUp
    //     );
    // }
}
