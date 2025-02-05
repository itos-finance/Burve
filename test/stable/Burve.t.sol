// SPDX-License-Identifier: BUSL-1.1
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
import {LiquidityCalculations} from "../../src/stable/lib/LiquidityCalculations.sol";

contract BurveTest is ForkableTest {
    Burve public burveIsland; // island only
    Burve public burveV3; // v3 only
    Burve public burve; // island + v3

    IUniswapV3Pool pool;
    IERC20 token0;
    IERC20 token1;

    function forkSetup() internal virtual override {
        // Pool info
        pool = IUniswapV3Pool(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3
        );
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        int24 tickSpacing = pool.tickSpacing();
        int24 clampedCurrentTick = getClampedCurrentTick();

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

        // Burve
        int24 rangeWidth = 100 * tickSpacing;
        TickRange[] memory ranges = new TickRange[](2);
        ranges[0] = TickRange(0, 0);
        ranges[1] = TickRange(
            clampedCurrentTick - rangeWidth,
            clampedCurrentTick + rangeWidth
        );

        uint128[] memory weights = new uint128[](2);
        weights[0] = 3;
        weights[1] = 1;

        burve = new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            BartioAddresses.KODIAK_HONEY_NECT_ISLAND,
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
    // - mint
    // - burn
    // - getInfo

    // Contructor Tests

    function testBurveIslandSetup() public view forkOnly {
        assertEq(address(burveIsland.pool()), address(pool), "burveIsland pool address");
        assertEq(address(burveIsland.token0()), address(token0), "burveIsland token0 address");
        assertEq(address(burveIsland.token1()), address(token1), "burveIsland token1 address");

        assertEq(address(burveIsland.island()), BartioAddresses.KODIAK_HONEY_NECT_ISLAND, "burveIsland island address");

        (int24 lower, int24 upper) = burveIsland.ranges(0);
        assertEq(lower, 0, "burveIsland range 0 lower");
        assertEq(upper, 0, "burveIsland range 0 upper");

        assertEq(
            burveV3.distX96(0),
            1 << 96,
            "burveIsland distX96 0"
        ); // 1/1
    }

    function testBurveV3Setup() public view forkOnly {
        assertEq(address(burveV3.pool()), address(pool), "burveV3 pool address");
        assertEq(address(burveV3.token0()), address(token0), "burveV3 token0 address");
        assertEq(address(burveV3.token1()), address(token1), "burveV3 token1 address");

        assertEq(address(burveV3.island()), address(0x0), "burveV3 island address");

        int24 tickSpacing = pool.tickSpacing();
        int24 clampedCurrentTick = getClampedCurrentTick();
        int24 rangeWidth = 10 * tickSpacing;

        (int24 lower, int24 upper) = burveV3.ranges(0);
        assertEq(lower, clampedCurrentTick - rangeWidth, "burveV3 range 0 lower");
        assertEq(upper, clampedCurrentTick + rangeWidth, "burveV3 range 0 upper");

        assertEq(
            burveV3.distX96(0),
            1 << 96,
            "burveV3 distX96 0"
        ); // 1/1
    }

    function testBurveSetup() public view forkOnly {
        assertEq(address(burve.pool()), address(pool), "burve pool address");
        assertEq(address(burve.token0()), address(token0), "burve token0 address");
        assertEq(address(burve.token1()), address(token1), "burve token1 address");

        assertEq(address(burve.island()), address(BartioAddresses.KODIAK_HONEY_NECT_ISLAND), "burve island address");

        int24 tickSpacing = pool.tickSpacing();
        int24 clampedCurrentTick = getClampedCurrentTick();
        int24 rangeWidth = 100 * tickSpacing;

        (int24 lower, int24 upper) = burve.ranges(0);
        assertEq(lower, 0, "burve range 0 lower");
        assertEq(upper, 0, "burve range 0 upper");
        (lower, upper) = burve.ranges(1);
        assertEq(lower, clampedCurrentTick - rangeWidth, "burve range 1 lower");
        assertEq(upper, clampedCurrentTick + rangeWidth, "burve range 1 upper");

        assertEq(
            burve.distX96(0),
            59421121885698253195157962752,
            "burve distX96 0"
        ); // 3/4
        assertEq(
            burve.distX96(1),
            19807040628566084398385987584,
            "burve distX96 1"
        ); // 1/4
    }

    function testCreateRevertPoolIsZeroAddress() public forkOnly {
        vm.expectRevert(Burve.PoolIsZeroAddress.selector);
        
        new Burve(address(0x0), address(0x0), new TickRange[](0), new uint128[](0));
    }

    function testCreateRevertMismatchIslandPool() public forkOnly {
        address poolAddr = BartioAddresses.KODIAK_HONEY_NECT_POOL_V3;
        address islandAddr = BartioAddresses.KODIAK_BERA_YEET_ISLAND_NEW;
        
        vm.expectRevert(abi.encodeWithSelector(Burve.MismatchedIslandPool.selector, islandAddr, poolAddr));
        
        new Burve(poolAddr, islandAddr, new TickRange[](0), new uint128[](0));
    }

    function testCreateRevertMismatchedRangeWeightLengths() public forkOnly {
        vm.expectRevert(abi.encodeWithSelector(Burve.MismatchedRangeWeightLengths.selector, 1, 0));
        
        new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            address(0x0), 
            new TickRange[](1), 
            new uint128[](0)
        );
    }

    function testCreateRevertIslandRangeWithNoIsland() public forkOnly {
        TickRange[] memory ranges = new TickRange[](1);
        ranges[0] = TickRange(0, 0);

        uint128[] memory weights = new uint128[](1);
        weights[0] = 3;

        vm.expectRevert(Burve.NoIsland.selector);

        new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            address(0x0), 
            ranges, 
            weights
        );
    }

    function testCreateRevertInvalidRangeLower() public forkOnly {
        int24 tickSpacing = pool.tickSpacing();
 
        TickRange[] memory ranges = new TickRange[](1);
        ranges[0] = TickRange(tickSpacing - 1, tickSpacing * 2);

        uint128[] memory weights = new uint128[](1);
        weights[0] = 3;

        vm.expectRevert(abi.encodeWithSelector(Burve.InvalidRange.selector, ranges[0].lower, ranges[0].upper));

        new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            BartioAddresses.KODIAK_HONEY_NECT_ISLAND, 
            ranges, 
            weights
        );
    }

    function testCreateRevertInvalidRangeUpper() public forkOnly {
        int24 tickSpacing = pool.tickSpacing();
 
        TickRange[] memory ranges = new TickRange[](1);
        ranges[0] = TickRange(tickSpacing, tickSpacing * 2 + 1);

        uint128[] memory weights = new uint128[](1);
        weights[0] = 3;

        vm.expectRevert(abi.encodeWithSelector(Burve.InvalidRange.selector, ranges[0].lower, ranges[0].upper));

        new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            BartioAddresses.KODIAK_HONEY_NECT_ISLAND, 
            ranges, 
            weights
        );
    }

    // Mint Tests

    // island mint
    // - msg.sender is approved address / user 
    // - token0 / token1 amounts transfered from msg.sender 
    // - Burve LP token sent to recipient 
    // - Island LP token sent to recipient 

    function testIslandMintSenderIsRecipient() public {
        address user = address(0xabc);
        uint128 liq = 10_000;

        (uint256 mint0, uint256 mint1, uint256 mintShares) = LiquidityCalculations
            .getAmountsFromIslandLiquidity(burveIsland.island(), liq);

        deal(address(token0), address(user), mint0);
        deal(address(token1), address(user), mint1);

        vm.startPrank(user);
    
        token0.approve(address(burveIsland), mint0);
        token1.approve(address(burveIsland), mint1);

        burveIsland.mint(address(user), liq);

        vm.stopPrank();

        assertEq(token0.balanceOf(address(user)), 0, "user token0 balance");
        assertEq(token1.balanceOf(address(user)), 0, "user token1 balance");
        assertEq(
            IERC20(burveIsland.island()).balanceOf(user),
            mintShares,
            "user island LP balance"
        );
        assertEq(
            IERC20(burveIsland).balanceOf(user),
            liq,
            "user burve LP balance"
        );
    }

    function testIslandMintSenderNotRecipient() public {
        address sender = address(this);
        address user = address(0xabc);
        uint128 liq = 10_000;

        (uint256 mint0, uint256 mint1, uint256 mintShares) = LiquidityCalculations
            .getAmountsFromIslandLiquidity(burveIsland.island(), liq);

        deal(address(token0), sender, mint0);
        deal(address(token1), sender, mint1);

        token0.approve(address(burveIsland), mint0);
        token1.approve(address(burveIsland), mint1);

        burveIsland.mint(address(user), liq);

        assertEq(token0.balanceOf(address(sender)), 0, "sender token0 balance");
        assertEq(token1.balanceOf(address(sender)), 0, "sender token1 balance");
        assertEq(
            IERC20(burveIsland.island()).balanceOf(user),
            mintShares,
            "user island LP balance"
        );
        assertEq(
            IERC20(burveIsland).balanceOf(user),
            liq,
            "user burve LP balance"
        );
    }

    function testV3MintSenderIsRecipient() public {
        address sender = address(this);
        address user = address(0xabc);
        uint128 liq = 10_000;

        (int24 lower, int24 upper) = burveV3.ranges(0);
        (uint256 mint0, uint256 mint1) = getAmountsFromRangeLiquidity(TickRange(lower, upper), liq);

        deal(address(token0), address(sender), mint0);
        deal(address(token1), address(sender), mint1);
    
        token0.approve(address(burveV3), mint0);
        token1.approve(address(burveV3), mint1);

        burveV3.mint(address(user), liq);

        assertEq(token0.balanceOf(address(sender)), 0, "sende token0 balance");
        assertEq(token1.balanceOf(address(sender)), 0, "sende token1 balance");
        assertEq(
            IERC20(burveV3).balanceOf(user),
            liq,
            "user burve LP balance"
        );
    }

    function testV3MintSenderNotRecipient() public {
        address user = address(0xabc);
        uint128 liq = 10_000;

        (int24 lower, int24 upper) = burveV3.ranges(0);
        (uint256 mint0, uint256 mint1) = getAmountsFromRangeLiquidity(TickRange(lower, upper), liq);

        deal(address(token0), address(user), mint0);
        deal(address(token1), address(user), mint1);

        vm.startPrank(user);
    
        token0.approve(address(burveV3), mint0);
        token1.approve(address(burveV3), mint1);

        burveV3.mint(address(user), liq);

        vm.stopPrank();

        assertEq(token0.balanceOf(address(user)), 0, "user token0 balance");
        assertEq(token1.balanceOf(address(user)), 0, "user token1 balance");
        assertEq(
            IERC20(burveV3).balanceOf(user),
            liq,
            "user burve LP balance"
        );
    }

    // island burn
    // ERC20(address(burveIsland.island())).approve(address(burveIsland), 10_000e18);
    // burveIsland.burn(1000);

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
        burveV3.burn(1000);

        vm.stopPrank();
    }

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

    // Helpers 

    function getClampedCurrentTick() internal view returns (int24) {
        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        return currentTick - (currentTick % tickSpacing);
    }

    /// @dev rounds up
    function getAmountsFromRangeLiquidity(
        TickRange memory range,
        uint128 liquidity
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(range.lower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(range.upper);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity,
            true
        );
    }
}
