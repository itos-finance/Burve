// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Burve, TickRange, TickRangeImpl, Info} from "../../src/stable/Burve.sol";
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
import {FullMath} from "../../src/multi/FullMath.sol";

contract BurveTest is ForkableTest {
    Burve public burveIsland; // island only
    Burve public burveV3; // v3 only
    Burve public burve; // island + v3

    IUniswapV3Pool pool;
    IERC20 token0;
    IERC20 token1;

    uint256 private constant X96MASK = (1 << 96) - 1;

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

    // Contructor Tests

    function testIslandSetup() public view forkOnly {
        assertEq(address(burveIsland.pool()), address(pool), "pool address");
        assertEq(address(burveIsland.token0()), address(token0), "token0 address");
        assertEq(address(burveIsland.token1()), address(token1), "token1 address");

        assertEq(address(burveIsland.island()), BartioAddresses.KODIAK_HONEY_NECT_ISLAND, "island address");

        (int24 lower, int24 upper) = burveIsland.ranges(0);
        assertEq(lower, 0, "range 0 lower");
        assertEq(upper, 0, "range 0 upper");

        assertEq(
            burveV3.distX96(0),
            1 << 96,
            "distX96 0"
        ); // 1/1
    }

    function testV3Setup() public view forkOnly {
        assertEq(address(burveV3.pool()), address(pool), "pool address");
        assertEq(address(burveV3.token0()), address(token0), "token0 address");
        assertEq(address(burveV3.token1()), address(token1), "token1 address");

        assertEq(address(burveV3.island()), address(0x0), "island address");

        int24 tickSpacing = pool.tickSpacing();
        int24 clampedCurrentTick = getClampedCurrentTick();
        int24 rangeWidth = 10 * tickSpacing;

        (int24 lower, int24 upper) = burveV3.ranges(0);
        assertEq(lower, clampedCurrentTick - rangeWidth, "range 0 lower");
        assertEq(upper, clampedCurrentTick + rangeWidth, "range 0 upper");

        assertEq(
            burveV3.distX96(0),
            1 << 96,
            "distX96 0"
        ); // 1/1
    }

    function testSetup() public view forkOnly {
        assertEq(address(burve.pool()), address(pool), "pool address");
        assertEq(address(burve.token0()), address(token0), "token0 address");
        assertEq(address(burve.token1()), address(token1), "token1 address");

        assertEq(address(burve.island()), address(BartioAddresses.KODIAK_HONEY_NECT_ISLAND), "island address");

        int24 tickSpacing = pool.tickSpacing();
        int24 clampedCurrentTick = getClampedCurrentTick();
        int24 rangeWidth = 100 * tickSpacing;

        (int24 lower, int24 upper) = burve.ranges(0);
        assertEq(lower, 0, "range 0 lower");
        assertEq(upper, 0, "range 0 upper");
        (lower, upper) = burve.ranges(1);
        assertEq(lower, clampedCurrentTick - rangeWidth, "range 1 lower");
        assertEq(upper, clampedCurrentTick + rangeWidth, "range 1 upper");

        assertEq(
            burve.distX96(0),
            59421121885698253195157962752,
            "distX96 0"
        ); // 3/4
        assertEq(
            burve.distX96(1),
            19807040628566084398385987584,
            "distX96 1"
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

    function testIslandMintSenderIsRecipient() public {
        address user = address(0xabc);
        uint128 liq = 10_000;

        (uint256 mint0, uint256 mint1, uint256 mintShares) = LiquidityCalculations
            .getMintAmountsFromIslandLiquidity(burveIsland.island(), liq);

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
            .getMintAmountsFromIslandLiquidity(burveIsland.island(), liq);

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
        address user = address(0xabc);
        uint128 liq = 10_000;

        (int24 lower, int24 upper) = burveV3.ranges(0);
        (uint256 mint0, uint256 mint1) = getAmountsFromLiquidity(liq, lower, upper, true);

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

    function testV3MintSenderNotRecipient() public {
        address sender = address(this);
        address user = address(0xabc);
        uint128 liq = 10_000;

        (int24 lower, int24 upper) = burveV3.ranges(0);
        (uint256 mint0, uint256 mint1) = getAmountsFromLiquidity(liq, lower, upper, true);

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

    function testMintSenderIsRecipient() public {
        address user = address(0xabc);
        uint128 liq = 10_000;

        // island liq
        uint128 islandLiq = uint128(shift96(liq * burve.distX96(0), true));
        (uint256 islandMint0, uint256 islandMint1, uint256 islandMintShares) = LiquidityCalculations
            .getMintAmountsFromIslandLiquidity(burve.island(), islandLiq);

        // v3 liq
        uint128 v3Liq = uint128(shift96(liq * burve.distX96(1), true));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsFromLiquidity(v3Liq, lower, upper, true);

        uint256 mint0 = islandMint0 + v3Mint0;
        uint256 mint1 = islandMint1 + v3Mint1;

        deal(address(token0), address(user), mint0);
        deal(address(token1), address(user), mint1);

        vm.startPrank(user);
    
        token0.approve(address(burve), mint0);
        token1.approve(address(burve), mint1);

        burve.mint(address(user), liq);

        vm.stopPrank();

        assertEq(token0.balanceOf(address(user)), 0, "user token0 balance");
        assertEq(token1.balanceOf(address(user)), 0, "user token1 balance");
        assertEq(
            IERC20(burve.island()).balanceOf(user),
            islandMintShares,
            "user island LP balance"
        );
        assertEq(
            IERC20(burve).balanceOf(user),
            liq,
            "user burve LP balance"
        );
    }

    function testMintSenderNotRecipient() public {
        address sender = address(this);
        address user = address(0xabc);
        uint128 liq = 10_000;

        // island liq
        uint128 islandLiq = uint128(shift96(liq * burve.distX96(0), true));
        (uint256 islandMint0, uint256 islandMint1, uint256 islandMintShares) = LiquidityCalculations
            .getMintAmountsFromIslandLiquidity(burve.island(), islandLiq);

        // v3 liq
        uint128 v3Liq = uint128(shift96(liq * burve.distX96(1), true));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsFromLiquidity(v3Liq, lower, upper, true);

        uint256 mint0 = islandMint0 + v3Mint0;
        uint256 mint1 = islandMint1 + v3Mint1;

        deal(address(token0), address(sender), mint0);
        deal(address(token1), address(sender), mint1);
    
        token0.approve(address(burve), mint0);
        token1.approve(address(burve), mint1);

        burve.mint(address(user), liq);

        assertEq(token0.balanceOf(address(sender)), 0, "sender token0 balance");
        assertEq(token1.balanceOf(address(sender)), 0, "sender token1 balance");
        assertEq(
            IERC20(burve.island()).balanceOf(user),
            islandMintShares,
            "user island LP balance"
        );
        assertEq(
            IERC20(burve).balanceOf(user),
            liq,
            "user burve LP balance"
        );
    }

    // Burn Tests 

    function testBurnIslandFull() public {
        address sender = address(this);
        address user = address(0xabc);
        uint128 liq = 10_000;
        IKodiakIsland island = burveIsland.island();

        // mint

        (uint256 mint0, uint256 mint1, ) = LiquidityCalculations.getMintAmountsFromIslandLiquidity(island, liq);

        deal(address(token0), sender, mint0);
        deal(address(token1), sender, mint1);

        token0.approve(address(burveIsland), mint0);
        token1.approve(address(burveIsland), mint1);

        burveIsland.mint(address(user), liq);

        assertEq(token0.balanceOf(address(user)), 0, "user token0 balance");
        assertEq(token1.balanceOf(address(user)), 0, "user token1 balance");

        // burn

        vm.startPrank(user);

        // approve Island LP tokens for transfer to Burve
        uint256 islandLPBalance = island.balanceOf(user);
        island.approve(address(burveIsland), islandLPBalance);

        burveIsland.burn(liq);

        vm.stopPrank();

        uint128 burnLiq = islandSharesToLiquidity(island, islandLPBalance);
        (uint256 burn0, uint256 burn1) = getAmountsFromLiquidity(burnLiq, island.lowerTick(), island.upperTick(), false);

        assertGe(token0.balanceOf(address(user)), burn0, "burn user token0 balance");
        assertGe(token1.balanceOf(address(user)), burn1, "burn user token1 balance");
        assertEq(
            IERC20(burveIsland.island()).balanceOf(user),
            0,
            "user island LP balance"
        );
        assertEq(
            IERC20(burveIsland).balanceOf(user),
            0,
            "user burve LP balance"
        );
    }

    function testBurnIslandPartial() public {
        address sender = address(this);
        address user = address(0xabc);
        uint128 mintLiq = 10_000;
        uint128 burnLiq = 1_000;
        IKodiakIsland island = burveIsland.island();

        // mint

        (uint256 mint0, uint256 mint1, uint256 mintShares) = LiquidityCalculations.getMintAmountsFromIslandLiquidity(island, mintLiq);

        deal(address(token0), sender, mint0);
        deal(address(token1), sender, mint1);

        token0.approve(address(burveIsland), mint0);
        token1.approve(address(burveIsland), mint1);

        burveIsland.mint(address(user), mintLiq);

        assertEq(token0.balanceOf(address(user)), 0, "user token0 balance");
        assertEq(token1.balanceOf(address(user)), 0, "user token1 balance");

        // burn

        vm.startPrank(user);

        // approve Island LP tokens for transfer to Burve
        (,, uint256 burnShares) = LiquidityCalculations.getMintAmountsFromIslandLiquidity(island, burnLiq);
        island.approve(address(burveIsland), burnShares);

        burveIsland.burn(burnLiq);

        vm.stopPrank();

        uint128 islandBurnLiq = islandSharesToLiquidity(island, burnShares);
        (uint256 burn0, uint256 burn1) = getAmountsFromLiquidity(islandBurnLiq, island.lowerTick(), island.upperTick(), false);

        assertGe(token0.balanceOf(address(user)), burn0, "burn user token0 balance");
        assertGe(token1.balanceOf(address(user)), burn1, "burn user token1 balance");
        assertEq(
            IERC20(burveIsland.island()).balanceOf(user),
            mintShares - burnShares,
            "user island LP balance"
        );
        assertEq(
            IERC20(burveIsland).balanceOf(user),
            mintLiq - burnLiq,
            "user burve LP balance"
        );
    }

    function testBurnV3Full() public {
        address sender = address(this);
        address user = address(0xabc);
        uint128 liq = 10_000;

        (int24 lower, int24 upper) = burveV3.ranges(0);

        // mint 

        (uint256 mint0, uint256 mint1) = getAmountsFromLiquidity(liq, lower, upper, true);

        deal(address(token0), address(sender), mint0);
        deal(address(token1), address(sender), mint1);
    
        token0.approve(address(burveV3), mint0);
        token1.approve(address(burveV3), mint1);

        burveV3.mint(address(user), liq);

        assertEq(token0.balanceOf(address(user)), 0, "user token0 balance");
        assertEq(token1.balanceOf(address(user)), 0, "user token1 balance");

        // burn

        vm.prank(user);
        burveV3.burn(liq);

        (uint256 burn0, uint256 burn1) = getAmountsFromLiquidity(liq, lower, upper, false);

        assertEq(token0.balanceOf(address(user)), burn0, "burn user token0 balance");
        assertEq(token1.balanceOf(address(user)), burn1, "burn user token1 balance");
        assertEq(
            IERC20(burveIsland).balanceOf(user),
            0,
            "user burve LP balance"
        );
    }

    function testBurnV3Partial() public {
        address sender = address(this);
        address user = address(0xabc);
        uint128 mintLiq = 10_000;
        uint128 burnLiq = 1_000;

        (int24 lower, int24 upper) = burveV3.ranges(0);

        // mint 

        (uint256 mint0, uint256 mint1) = getAmountsFromLiquidity(mintLiq, lower, upper, true);

        deal(address(token0), address(sender), mint0);
        deal(address(token1), address(sender), mint1);
    
        token0.approve(address(burveV3), mint0);
        token1.approve(address(burveV3), mint1);

        burveV3.mint(address(user), mintLiq);

        assertEq(token0.balanceOf(address(user)), 0, "user token0 balance");
        assertEq(token1.balanceOf(address(user)), 0, "user token1 balance");

        // burn

        vm.prank(user);
        burveV3.burn(burnLiq);

        (uint256 burn0, uint256 burn1) = getAmountsFromLiquidity(burnLiq, lower, upper, false);

        assertEq(token0.balanceOf(address(user)), burn0, "burn user token0 balance");
        assertEq(token1.balanceOf(address(user)), burn1, "burn user token1 balance");
        assertEq(
            IERC20(burveV3).balanceOf(user),
            mintLiq - burnLiq,
            "user burve LP balance"
        );
    }

    function testBurnFull() public {
        address sender = address(this);
        address user = address(0xabc);
        uint128 liq = 10_000;
        IKodiakIsland island = burve.island();

        // island mint amounts
        uint128 islandMintLiq = uint128(shift96(liq * burve.distX96(0), true));
        (uint256 islandMint0, uint256 islandMint1, ) = LiquidityCalculations.getMintAmountsFromIslandLiquidity(island, islandMintLiq);

        // v3 mint amounts
        uint128 v3Liq = uint128(shift96(liq * burve.distX96(1), true));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsFromLiquidity(v3Liq, lower, upper, true);

        // mint

        uint256 mint0 = islandMint0 + v3Mint0;
        uint256 mint1 = islandMint1 + v3Mint1;

        deal(address(token0), address(sender), mint0);
        deal(address(token1), address(sender), mint1);
    
        token0.approve(address(burve), mint0);
        token1.approve(address(burve), mint1);

        burve.mint(address(user), liq);

        assertEq(token0.balanceOf(address(user)), 0, "user token0 balance");
        assertEq(token1.balanceOf(address(user)), 0, "user token1 balance");

        // burn

        vm.startPrank(user);

        // approve Island LP tokens for transfer to Burve
        uint256 islandLPBalance = island.balanceOf(user);
        island.approve(address(burve), islandLPBalance);

        burve.burn(liq);

        vm.stopPrank();

        // island burn amounts
        uint128 islandBurnLiq = islandSharesToLiquidity(island, islandLPBalance);
        (uint256 islandBurn0, uint256 islandBurn1) = getAmountsFromLiquidity(islandBurnLiq, island.lowerTick(), island.upperTick(), false);
        
        // v3 burn amounts
        (uint256 v3Burn0, uint256 v3Burn1) = getAmountsFromLiquidity(v3Liq, lower, upper, false);

        uint256 burn0 = islandBurn0 + v3Burn0;
        uint256 burn1 = islandBurn1 + v3Burn1;

        assertGe(token0.balanceOf(address(user)), burn0, "burn user token0 balance");
        assertGe(token1.balanceOf(address(user)), burn1, "burn user token1 balance");
        assertEq(
            IERC20(burve.island()).balanceOf(user),
            0,
            "user island LP balance"
        );
        assertEq(
            IERC20(burve).balanceOf(user),
            0,
            "user burve LP balance"
        );
    }

    function testBurnPartial() public {
        address sender = address(this);
        address user = address(0xabc);
        uint128 mintLiq = 10_000;
        uint128 burnLiq = 1_000;
        IKodiakIsland island = burve.island();

        // island mint amounts
        uint128 islandMintLiq = uint128(shift96(mintLiq * burve.distX96(0), true));
        (uint256 islandMint0, uint256 islandMint1, uint256 islandMintShares) = LiquidityCalculations.getMintAmountsFromIslandLiquidity(island, islandMintLiq);

        // v3 mint amounts
        uint128 v3MintLiq = uint128(shift96(mintLiq * burve.distX96(1), true));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsFromLiquidity(v3MintLiq, lower, upper, true);

        // mint 

        uint256 mint0 = islandMint0 + v3Mint0;
        uint256 mint1 = islandMint1 + v3Mint1;

        deal(address(token0), address(sender), mint0);
        deal(address(token1), address(sender), mint1);
    
        token0.approve(address(burve), mint0);
        token1.approve(address(burve), mint1);

        burve.mint(address(user), mintLiq);

        assertEq(token0.balanceOf(address(user)), 0, "user token0 balance");
        assertEq(token1.balanceOf(address(user)), 0, "user token1 balance");

        // burn

        vm.startPrank(user);

        // approve Island LP tokens for transfer to Burve
        uint128 islandBurnLiq = uint128(shift96(burnLiq * burve.distX96(0), true));
        (,, uint256 islandBurnShares) = LiquidityCalculations.getMintAmountsFromIslandLiquidity(island, islandBurnLiq);
        island.approve(address(burve), islandBurnShares);

        burve.burn(burnLiq);

        vm.stopPrank();

        // island burn amounts
        uint128 islandLiqFromBurnShares = islandSharesToLiquidity(island, islandBurnShares);
        (uint256 islandBurn0, uint256 islandBurn1) = getAmountsFromLiquidity(islandLiqFromBurnShares, island.lowerTick(), island.upperTick(), false);
        
        // v3 burn amounts
        uint128 v3BurnLiq = uint128(shift96(burnLiq * burve.distX96(1), true));
        (uint256 v3Burn0, uint256 v3Burn1) = getAmountsFromLiquidity(v3BurnLiq, lower, upper, false);

        uint256 burn0 = islandBurn0 + v3Burn0;
        uint256 burn1 = islandBurn1 + v3Burn1;

        assertGe(token0.balanceOf(address(user)), burn0, "burn user token0 balance");
        assertGe(token1.balanceOf(address(user)), burn1, "burn user token1 balance");
        assertEq(
            IERC20(burve.island()).balanceOf(user),
            islandMintShares - islandBurnShares,
            "user island LP balance"
        );
        assertEq(
            IERC20(burve).balanceOf(user),
            mintLiq - burnLiq,
            "user burve LP balance"
        );
    }

    // Get Info Tests 

    function testIslandGetInfo() public view forkOnly {
        Info memory info = burveIsland.getInfo();

        assertEq(info.pool, address(pool), "pool address");

        assertEq(info.island, BartioAddresses.KODIAK_HONEY_NECT_ISLAND, "island address");

        assertEq(info.ranges.length, 1, "ranges length");
        assertEq(info.ranges[0].lower, 0, "range 0 lower");
        assertEq(info.ranges[0].upper, 0, "range 0 upper");

        assertEq(info.distX96.length, 1, "distX96 length");
        assertEq(info.distX96[0], 1 << 96, "distX96 0");
    }

    function testV3GetInfo() public view forkOnly {
        Info memory info = burveV3.getInfo();

        assertEq(info.pool, address(pool), "pool address");

        assertEq(info.island, address(0x0), "island address");

        int24 tickSpacing = pool.tickSpacing();
        int24 clampedCurrentTick = getClampedCurrentTick();
        int24 rangeWidth = 10 * tickSpacing;

        assertEq(info.ranges.length, 1, "ranges length");
        assertEq(info.ranges[0].lower, clampedCurrentTick - rangeWidth, "range 0 lower");
        assertEq(info.ranges[0].upper, clampedCurrentTick + rangeWidth, "range 0 upper");

        assertEq(info.distX96.length, 1, "distX96 length");
        assertEq(info.distX96[0], 1 << 96, "distX96 0");
    }

    function testGetInfo() public view forkOnly {
        Info memory info = burve.getInfo();

        assertEq(info.pool, address(pool), "pool address");

        assertEq(info.island, BartioAddresses.KODIAK_HONEY_NECT_ISLAND, "island address");

        int24 tickSpacing = pool.tickSpacing();
        int24 clampedCurrentTick = getClampedCurrentTick();
        int24 rangeWidth = 100 * tickSpacing;

        assertEq(info.ranges.length, 2, "ranges length");
        assertEq(info.ranges[0].lower, 0, "range 0 lower");
        assertEq(info.ranges[0].upper, 0, "range 0 upper");
        assertEq(info.ranges[1].lower, clampedCurrentTick - rangeWidth, "range 0 lower");
        assertEq(info.ranges[1].upper, clampedCurrentTick + rangeWidth, "range 0 upper");

        assertEq(info.distX96.length, 2, "distX96 length");
        assertEq(info.distX96[0], 59421121885698253195157962752, "distX96 0"); // 3/4
        assertEq(info.distX96[1], 19807040628566084398385987584, "distX96 1"); // 1/4
    }

    // Helpers 

    /// @notice Calculates the liquidity represented by island shares
    /// @param island The island
    /// @param shares The shares
    /// @return liquidity The liquidity
    function islandSharesToLiquidity(IKodiakIsland island, uint256 shares) internal view returns (uint128 liquidity) {
        bytes32 positionId = island.getPositionID();
        (uint128 poolLiquidity,,,,) = pool.positions(positionId);
        uint256 totalSupply = island.totalSupply();
        liquidity = uint128(FullMath.mulDiv(shares, poolLiquidity, totalSupply));
    }

    /// @notice Gets the current tick clamped to respect the tick spacing
    function getClampedCurrentTick() internal view returns (int24) {
        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        return currentTick - (currentTick % tickSpacing);
    }

    /// @notice Calculates token amounts for the given liquidity. 
    /// @param liquidity The liquidity
    /// @param lower The lower tick
    /// @param upper The upper tick
    /// @param roundUp Whether to round up the amounts
    function getAmountsFromLiquidity(
        uint128 liquidity,
        int24 lower,
        int24 upper,
        bool roundUp
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(lower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(upper);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity,
            roundUp
        );
    }

    function shift96(
        uint256 a,
        bool roundUp
    ) internal pure returns (uint256 b) {
        b = a >> 96;
        if (roundUp && (a & X96MASK) > 0) b += 1;
    }
}
