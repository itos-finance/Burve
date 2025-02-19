// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {AdminLib} from "Commons/Util/Admin.sol";
import {ForkableTest} from "Commons/Test/ForkableTest.sol";

import {BartioAddresses} from "../utils/BaritoAddresses.sol";
import {Burve} from "../../src/single/Burve.sol";
import {BurveExposedInternal} from "./BurveExposedInternal.sol";
import {FullMath} from "../../src/FullMath.sol";
import {IKodiakIsland} from "../../src/single/integrations/kodiak/IKodiakIsland.sol";
import {IStationProxy} from "../../src/single/IStationProxy.sol";
import {IUniswapV3Pool} from "../../src/single/integrations/kodiak/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "../../src/single/integrations/uniswap/LiquidityAmounts.sol";
import {NullStationProxy} from "./NullStationProxy.sol";
import {TickMath} from "../../src/single/integrations/uniswap/TickMath.sol";
import {TickRange} from "../../src/single/TickRange.sol";

contract BurveTest is ForkableTest {
    uint256 private constant X96_MASK = (1 << 96) - 1;
    uint256 private constant UNIT_NOMINAL_LIQ_X64 = 1 << 64;

    BurveExposedInternal public burveIsland; // island only
    BurveExposedInternal public burveV3; // v3 only
    BurveExposedInternal public burve; // island + v3
    BurveExposedInternal public burveCompound; // island + v3 (mocked uni pool)

    IUniswapV3Pool pool;
    IERC20 token0;
    IERC20 token1;

    IStationProxy stationProxy;

    address alice;
    address sender;

    function forkSetup() internal virtual override {
        alice = makeAddr("Alice");
        sender = makeAddr("Sender");

        stationProxy = new NullStationProxy();

        // Pool info
        pool = IUniswapV3Pool(BartioAddresses.KODIAK_HONEY_NECT_POOL_V3);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        int24 tickSpacing = pool.tickSpacing();
        int24 clampedCurrentTick = getClampedCurrentTick();

        // Burve Island
        TickRange[] memory islandRanges = new TickRange[](1);
        islandRanges[0] = TickRange(0, 0);

        uint128[] memory islandWeights = new uint128[](1);
        islandWeights[0] = 1;

        burveIsland = new BurveExposedInternal(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            BartioAddresses.KODIAK_HONEY_NECT_ISLAND,
            address(stationProxy),
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

        burveV3 = new BurveExposedInternal(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            address(0x0),
            address(stationProxy),
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

        burve = new BurveExposedInternal(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            BartioAddresses.KODIAK_HONEY_NECT_ISLAND,
            address(stationProxy),
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

    // Create Tests

    function testRevert_Create_InvalidRange_Lower() public forkOnly {
        int24 tickSpacing = pool.tickSpacing();

        TickRange[] memory ranges = new TickRange[](1);
        ranges[0] = TickRange(tickSpacing - 1, tickSpacing * 2);

        uint128[] memory weights = new uint128[](1);
        weights[0] = 3;

        vm.expectRevert(
            abi.encodeWithSelector(
                Burve.InvalidRange.selector,
                ranges[0].lower,
                ranges[0].upper
            )
        );

        new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            BartioAddresses.KODIAK_HONEY_NECT_ISLAND,
            address(stationProxy),
            ranges,
            weights
        );
    }

    function testRevert_Create_InvalidRange_Upper() public forkOnly {
        int24 tickSpacing = pool.tickSpacing();

        TickRange[] memory ranges = new TickRange[](1);
        ranges[0] = TickRange(tickSpacing, tickSpacing * 2 + 1);

        uint128[] memory weights = new uint128[](1);
        weights[0] = 3;

        vm.expectRevert(
            abi.encodeWithSelector(
                Burve.InvalidRange.selector,
                ranges[0].lower,
                ranges[0].upper
            )
        );

        new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            BartioAddresses.KODIAK_HONEY_NECT_ISLAND,
            address(stationProxy),
            ranges,
            weights
        );
    }

    // Migrate Station Proxy Tests

    function test_MigrateStationProxy() public {
        IStationProxy newStationProxy = new NullStationProxy();

        vm.expectCall(
            address(burve.stationProxy()),
            abi.encodeCall(IStationProxy.migrate, (newStationProxy))
        );

        vm.expectEmit(true, true, false, true);
        emit Burve.MigrateStationProxy(stationProxy, newStationProxy);

        burve.migrateStationProxy(newStationProxy);
        assertEq(
            address(burve.stationProxy()),
            address(newStationProxy),
            "new station proxy"
        );
    }

    function testRevert_MigrateStationProxy_SenderNotOwner() public {
        IStationProxy newStationProxy = new NullStationProxy();
        vm.expectRevert(AdminLib.NotOwner.selector);
        vm.prank(alice);
        burve.migrateStationProxy(newStationProxy);
    }

    function testRevert_MigrateStationProxy_ToSameStationProxy() public {
        vm.expectRevert(Burve.MigrateToSameStationProxy.selector);
        burve.migrateStationProxy(stationProxy);
    }

    // Mint Tests

    function test_Mint_Island_SenderIsRecipient() public {
        uint128 liq = 10_000;
        IKodiakIsland island = burveIsland.island();

        // calc island mint
        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(
            liq,
            island.lowerTick(),
            island.upperTick(),
            true
        );
        (uint256 mint0, uint256 mint1, uint256 mintShares) = island
            .getMintAmounts(amount0, amount1);

        // deal required tokens
        deal(address(token0), address(alice), mint0);
        deal(address(token1), address(alice), mint1);

        vm.startPrank(alice);

        // approve transfer
        token0.approve(address(burveIsland), mint0);
        token1.approve(address(burveIsland), mint1);

        // check mint event
        vm.expectEmit(true, true, false, true);
        emit Burve.Mint(alice, alice, liq);

        // mint
        burveIsland.mint(address(alice), liq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burveIsland.totalNominalLiq(), liq, "total liq nominal");

        // check shares
        assertEq(burveIsland.totalShares(), liq, "total shares");

        // check pool token balances
        assertEq(token0.balanceOf(address(alice)), 0, "alice token0 balance");
        assertEq(token1.balanceOf(address(alice)), 0, "alice token1 balance");

        // check island LP token
        assertEq(
            burveIsland.islandSharesPerOwner(alice),
            mintShares,
            "alice islandSharesPerOwner balance"
        );
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(
            island.balanceOf(address(stationProxy)),
            mintShares,
            "station proxy island LP balance"
        );

        // check burve LP token
        assertEq(burveIsland.balanceOf(alice), liq, "alice burve LP balance");
    }

    function test_Mint_Island_SenderNotRecipient() public {
        uint128 liq = 10_000;
        IKodiakIsland island = burveIsland.island();

        // calc island mint
        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(
            liq,
            island.lowerTick(),
            island.upperTick(),
            true
        );
        (uint256 mint0, uint256 mint1, uint256 mintShares) = island
            .getMintAmounts(amount0, amount1);

        // deal required tokens
        deal(address(token0), sender, mint0);
        deal(address(token1), sender, mint1);

        vm.startPrank(sender);

        // approve transfer
        token0.approve(address(burveIsland), mint0);
        token1.approve(address(burveIsland), mint1);

        // check mint event
        vm.expectEmit(true, true, false, true);
        emit Burve.Mint(sender, alice, liq);

        // mint
        burveIsland.mint(address(alice), liq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burveIsland.totalNominalLiq(), liq, "total liq nominal");

        // check shares
        assertEq(burveIsland.totalShares(), liq, "total shares");

        // check pool token balances
        assertEq(token0.balanceOf(address(sender)), 0, "sender token0 balance");
        assertEq(token1.balanceOf(address(sender)), 0, "sender token1 balance");

        // check island LP token
        assertEq(
            burveIsland.islandSharesPerOwner(alice),
            mintShares,
            "alice islandSharesPerOwner balance"
        );
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(
            island.balanceOf(address(stationProxy)),
            mintShares,
            "station proxy island LP balance"
        );

        // check burve LP token
        assertEq(burveIsland.balanceOf(alice), liq, "alice burve LP balance");
    }

    function test_Mint_V3_SenderIsRecipient() public {
        uint128 liq = 10_000;

        // calc v3 mint
        (int24 lower, int24 upper) = burveV3.ranges(0);
        (uint256 mint0, uint256 mint1) = getAmountsForLiquidity(
            liq,
            lower,
            upper,
            true
        );

        // deal required tokens
        deal(address(token0), address(alice), mint0);
        deal(address(token1), address(alice), mint1);

        vm.startPrank(alice);

        // approve transfer
        token0.approve(address(burveV3), mint0);
        token1.approve(address(burveV3), mint1);

        // check mint event
        vm.expectEmit(true, true, false, true);
        emit Burve.Mint(alice, alice, liq);

        // mint
        burveV3.mint(address(alice), liq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burveV3.totalNominalLiq(), liq, "total liq nominal");

        // check shares
        assertEq(burveV3.totalShares(), liq, "total shares");

        // check pool token balances
        assertEq(token0.balanceOf(address(alice)), 0, "alice token0 balance");
        assertEq(token1.balanceOf(address(alice)), 0, "alice token1 balance");

        // check burve LP token
        assertEq(burveV3.balanceOf(alice), liq, "alice burve LP balance");
    }

    function test_Mint_V3_SenderNotRecipient() public {
        uint128 liq = 10_000;

        // calc v3 mint
        (int24 lower, int24 upper) = burveV3.ranges(0);
        (uint256 mint0, uint256 mint1) = getAmountsForLiquidity(
            liq,
            lower,
            upper,
            true
        );

        // deal required tokens
        deal(address(token0), address(sender), mint0);
        deal(address(token1), address(sender), mint1);

        vm.startPrank(sender);

        // approve transfer
        token0.approve(address(burveV3), mint0);
        token1.approve(address(burveV3), mint1);

        // check mint event
        vm.expectEmit(true, true, false, true);
        emit Burve.Mint(sender, alice, liq);

        // mint
        burveV3.mint(address(alice), liq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burveV3.totalNominalLiq(), liq, "total liq nominal");

        // check shares
        assertEq(burveV3.totalShares(), liq, "total shares");

        // check pool token balances
        assertEq(token0.balanceOf(address(sender)), 0, "sender token0 balance");
        assertEq(token1.balanceOf(address(sender)), 0, "sender token1 balance");

        // check burve LP token
        assertEq(burveV3.balanceOf(alice), liq, "alice burve LP balance");
    }

    function test_Mint_SenderIsRecipient() public {
        uint128 liq = 10_000;
        IKodiakIsland island = burve.island();

        // calc island mint
        uint128 islandLiq = uint128(shift96(liq * burve.distX96(0), true));
        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(
            islandLiq,
            island.lowerTick(),
            island.upperTick(),
            true
        );
        (
            uint256 islandMint0,
            uint256 islandMint1,
            uint256 islandMintShares
        ) = island.getMintAmounts(amount0, amount1);

        // calc v3 mint
        uint128 v3Liq = uint128(shift96(liq * burve.distX96(1), true));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsForLiquidity(
            v3Liq,
            lower,
            upper,
            true
        );

        // mint amounts
        uint256 mint0 = islandMint0 + v3Mint0;
        uint256 mint1 = islandMint1 + v3Mint1;

        // deal required tokens
        deal(address(token0), address(alice), mint0);
        deal(address(token1), address(alice), mint1);

        vm.startPrank(alice);

        // approve transfer
        token0.approve(address(burve), mint0);
        token1.approve(address(burve), mint1);

        // check mint event
        vm.expectEmit(true, true, false, true);
        emit Burve.Mint(alice, alice, liq);

        // mint
        burve.mint(address(alice), liq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burve.totalNominalLiq(), liq, "total liq nominal");

        // check shares
        assertEq(burve.totalShares(), liq, "total shares");

        // check pool token balances
        assertEq(token0.balanceOf(address(alice)), 0, "alice token0 balance");
        assertEq(token1.balanceOf(address(alice)), 0, "alice token1 balance");

        // check island LP token
        assertEq(
            burve.islandSharesPerOwner(alice),
            islandMintShares,
            "alice islandSharesPerOwner balance"
        );
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(
            island.balanceOf(address(stationProxy)),
            islandMintShares,
            "station proxy island LP balance"
        );

        // check burve LP token
        assertEq(burve.balanceOf(alice), liq, "alice burve LP balance");
    }

    function test_Mint_SenderNotRecipient() public {
        uint128 liq = 10_000;
        IKodiakIsland island = burve.island();

        // calc island mint
        uint128 islandLiq = uint128(shift96(liq * burve.distX96(0), true));
        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(
            islandLiq,
            island.lowerTick(),
            island.upperTick(),
            true
        );
        (
            uint256 islandMint0,
            uint256 islandMint1,
            uint256 islandMintShares
        ) = island.getMintAmounts(amount0, amount1);

        // calc v3 mint
        uint128 v3Liq = uint128(shift96(liq * burve.distX96(1), true));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsForLiquidity(
            v3Liq,
            lower,
            upper,
            true
        );

        // mint amounts
        uint256 mint0 = islandMint0 + v3Mint0;
        uint256 mint1 = islandMint1 + v3Mint1;

        // deal required tokens
        deal(address(token0), address(sender), mint0);
        deal(address(token1), address(sender), mint1);

        vm.startPrank(sender);

        // approve transfer
        token0.approve(address(burve), mint0);
        token1.approve(address(burve), mint1);

        // check mint event
        vm.expectEmit(true, true, false, true);
        emit Burve.Mint(sender, alice, liq);

        // mint
        burve.mint(address(alice), liq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burve.totalNominalLiq(), liq, "total liq nominal");

        // check shares
        assertEq(burve.totalShares(), liq, "total shares");

        // check pool token balances
        assertEq(token0.balanceOf(address(sender)), 0, "sender token0 balance");
        assertEq(token1.balanceOf(address(sender)), 0, "sender token1 balance");

        // check island LP token
        assertEq(
            burve.islandSharesPerOwner(alice),
            islandMintShares,
            "alice islandSharesPerOwner balance"
        );
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(
            island.balanceOf(address(stationProxy)),
            islandMintShares,
            "station proxy island LP balance"
        );

        // check burve LP token
        assertEq(burve.balanceOf(alice), liq, "alice burve LP balance");
    }

    function test_Mint_SubsequentShareCalc() public {
        // deal max tokens
        deal(address(token0), address(sender), type(uint256).max);
        deal(address(token1), address(sender), type(uint256).max);

        vm.startPrank(sender);

        // approve max transfer
        token0.approve(address(burve), type(uint256).max);
        token1.approve(address(burve), type(uint256).max);

        // 1st check mint event
        vm.expectEmit(true, true, false, true);
        emit Burve.Mint(sender, alice, 1000);

        // 1st mint
        burve.mint(address(alice), 1000, 0, type(uint128).max);

        // check 1st mint
        assertEq(burve.totalNominalLiq(), 1000, "total liq nominal 1st mint");
        assertEq(burve.totalShares(), 1000, "total shares 1st mint");
        assertEq(
            burve.balanceOf(alice),
            1000,
            "alice burve LP balance 1st mint"
        );

        // 2nd check mint event
        vm.expectEmit(true, true, false, true);
        emit Burve.Mint(sender, alice, 500);

        // 2nd mint (lower amount)
        burve.mint(address(alice), 500, 0, type(uint128).max);

        // check 2nd mint
        assertEq(burve.totalNominalLiq(), 1500, "total liq nominal 2nd mint");
        assertEq(burve.totalShares(), 1500, "total shares 2nd mint");
        assertEq(
            burve.balanceOf(alice),
            1500,
            "alice burve LP balance 2nd mint"
        );

        // 3rd check mint event
        vm.expectEmit(true, true, false, true);
        emit Burve.Mint(sender, alice, 3000);

        // 3rd mint (higher amount)
        burve.mint(address(alice), 3000, 0, type(uint128).max);

        // check 3rd mint
        assertEq(burve.totalNominalLiq(), 4500, "total liq nominal 3rd mint");
        assertEq(burve.totalShares(), 4500, "total shares 3rd mint");
        assertEq(
            burve.balanceOf(alice),
            4500,
            "alice burve LP balance 3rd mint"
        );

        vm.stopPrank();
    }

    function test_UniswapV3MintCallback() public {
        uint256 priorPoolBalance0 = token0.balanceOf(address(pool));
        uint256 priorPoolBalance1 = token1.balanceOf(address(pool));

        uint256 amount0Owed = 1e18;
        uint256 amount1Owed = 2e18;

        // deal required tokens
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

        // approve transfer
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

    function testRevert_UniswapV3MintCallbackSenderNotPool() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Burve.UniswapV3MintCallbackSenderNotPool.selector,
                address(this)
            )
        );
        burveV3.uniswapV3MintCallback(0, 0, abi.encode(address(this)));
    }

    function testRevert_Mint_SqrtPX96BelowLowerLimit() public {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 lowerSqrtPriceLimitX96 = sqrtRatioX96 + 100;
        uint160 upperSqrtPriceLimitX96 = sqrtRatioX96 + 200;
        vm.expectRevert(
            abi.encodeWithSelector(
                Burve.SqrtPriceX96OverLimit.selector,
                sqrtRatioX96,
                lowerSqrtPriceLimitX96,
                upperSqrtPriceLimitX96
            )
        );
        burve.mint(
            address(alice),
            100,
            lowerSqrtPriceLimitX96,
            upperSqrtPriceLimitX96
        );
    }

    function testRevert_Mint_SqrtPX96AboveUpperLimit() public {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 lowerSqrtPriceLimitX96 = sqrtRatioX96 - 200;
        uint160 upperSqrtPriceLimitX96 = sqrtRatioX96 - 100;
        vm.expectRevert(
            abi.encodeWithSelector(
                Burve.SqrtPriceX96OverLimit.selector,
                sqrtRatioX96,
                lowerSqrtPriceLimitX96,
                upperSqrtPriceLimitX96
            )
        );
        burve.mint(
            address(alice),
            100,
            lowerSqrtPriceLimitX96,
            upperSqrtPriceLimitX96
        );
    }

    // Burn Tests

    function test_Burn_IslandFull() public {
        uint128 mintLiq = 10_000;

        // Mint
        deal(address(token0), address(sender), type(uint256).max);
        deal(address(token1), address(sender), type(uint256).max);
        vm.startPrank(sender);
        token0.approve(address(burveIsland), type(uint256).max);
        token1.approve(address(burveIsland), type(uint256).max);
        burveIsland.mint(address(alice), mintLiq, 0, type(uint128).max);
        vm.stopPrank();

        // Burn
        IKodiakIsland island = burveIsland.island();

        // calc island burn
        uint128 islandBurnLiq = islandSharesToLiquidity(
            island,
            burveIsland.islandSharesPerOwner(alice)
        );
        (uint256 burn0, uint256 burn1) = getAmountsForLiquidity(
            islandBurnLiq,
            island.lowerTick(),
            island.upperTick(),
            false
        );

        vm.startPrank(alice);

        // approve transfer
        burveIsland.approve(address(burveIsland), mintLiq);

        // check burn event
        vm.expectEmit(true, false, false, true);
        emit Burve.Burn(alice, mintLiq);

        // burn
        burveIsland.burn(mintLiq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burveIsland.totalNominalLiq(), 0, "total liq nominal");

        // check shares
        assertEq(burveIsland.totalShares(), 0, "total shares");

        // check pool token balances
        assertGe(
            token0.balanceOf(address(alice)),
            burn0,
            "alice token0 balance"
        );
        assertGe(
            token1.balanceOf(address(alice)),
            burn1,
            "alice token1 balance"
        );

        // check island LP token
        assertEq(
            burveIsland.islandSharesPerOwner(alice),
            0,
            "alice islandSharesPerOwner balance"
        );
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(
            island.balanceOf(address(stationProxy)),
            0,
            "station proxy island LP balance"
        );

        // check burve LP token
        assertEq(burveIsland.balanceOf(alice), 0, "alice burve LP balance");
    }

    function test_Burn_IslandPartial() public {
        uint128 mintLiq = 10_000;
        uint128 burnLiq = 1_000;

        // Mint
        deal(address(token0), address(sender), type(uint256).max);
        deal(address(token1), address(sender), type(uint256).max);
        vm.startPrank(sender);
        token0.approve(address(burveIsland), type(uint256).max);
        token1.approve(address(burveIsland), type(uint256).max);
        burveIsland.mint(address(alice), mintLiq, 0, type(uint128).max);
        vm.stopPrank();

        // Burn
        IKodiakIsland island = burveIsland.island();

        // calc island burn
        uint256 islandShares = burveIsland.islandSharesPerOwner(alice);
        uint256 burnIslandShares = FullMath.mulDiv(
            islandShares,
            burnLiq,
            mintLiq
        );

        uint128 islandBurnLiq = islandSharesToLiquidity(
            island,
            burnIslandShares
        );
        (uint256 burn0, uint256 burn1) = getAmountsForLiquidity(
            islandBurnLiq,
            island.lowerTick(),
            island.upperTick(),
            false
        );

        vm.startPrank(alice);

        // approve transfer
        burveIsland.approve(address(burveIsland), burnLiq);

        // check burn event
        vm.expectEmit(true, false, false, true);
        emit Burve.Burn(alice, burnLiq);

        // burn
        burveIsland.burn(burnLiq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(
            burveIsland.totalNominalLiq(),
            mintLiq - burnLiq,
            "total liq nominal"
        );

        // check shares
        assertEq(burveIsland.totalShares(), mintLiq - burnLiq, "total shares");

        // check pool token balances
        assertGe(
            token0.balanceOf(address(alice)),
            burn0,
            "alice token0 balance"
        );
        assertGe(
            token1.balanceOf(address(alice)),
            burn1,
            "alice token1 balance"
        );

        // check island LP token
        assertEq(
            burveIsland.islandSharesPerOwner(alice),
            islandShares - burnIslandShares,
            "alice islandSharesPerOwner balance"
        );
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(
            island.balanceOf(address(stationProxy)),
            islandShares - burnIslandShares,
            "station proxy island LP balance"
        );

        // check burve LP token
        assertEq(
            burveIsland.balanceOf(alice),
            mintLiq - burnLiq,
            "alice burve LP balance"
        );
    }

    function test_Burn_V3Full() public {
        uint128 mintLiq = 10_000;

        // Mint
        deal(address(token0), address(sender), type(uint256).max);
        deal(address(token1), address(sender), type(uint256).max);
        vm.startPrank(sender);
        token0.approve(address(burveV3), type(uint256).max);
        token1.approve(address(burveV3), type(uint256).max);
        burveV3.mint(address(alice), mintLiq, 0, type(uint128).max);
        vm.stopPrank();

        // Burn

        // calc v3 burn
        (int24 lower, int24 upper) = burveV3.ranges(0);
        (uint256 burn0, uint256 burn1) = getAmountsForLiquidity(
            mintLiq,
            lower,
            upper,
            false
        );

        vm.startPrank(alice);

        // approve transfer
        burveV3.approve(address(burveV3), mintLiq);

        // check burn event
        vm.expectEmit(true, false, false, true);
        emit Burve.Burn(alice, mintLiq);

        // burn
        burveV3.burn(mintLiq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burveV3.totalNominalLiq(), 0, "total liq nominal");

        // check shares
        assertEq(burveV3.totalShares(), 0, "total shares");

        // check pool token balances
        assertGe(
            token0.balanceOf(address(alice)),
            burn0,
            "alice token0 balance"
        );
        assertGe(
            token1.balanceOf(address(alice)),
            burn1,
            "alice token1 balance"
        );

        // check burve LP token
        assertEq(burveIsland.balanceOf(alice), 0, "alice burve LP balance");
    }

    function test_Burn_V3Partial() public {
        uint128 mintLiq = 10_000;
        uint128 burnLiq = 1_000;

        // Mint
        deal(address(token0), address(sender), type(uint256).max);
        deal(address(token1), address(sender), type(uint256).max);
        vm.startPrank(sender);
        token0.approve(address(burveV3), type(uint256).max);
        token1.approve(address(burveV3), type(uint256).max);
        burveV3.mint(address(alice), mintLiq, 0, type(uint128).max);
        vm.stopPrank();

        // Burn

        // calc v3 burn
        (int24 lower, int24 upper) = burveV3.ranges(0);
        (uint256 burn0, uint256 burn1) = getAmountsForLiquidity(
            burnLiq,
            lower,
            upper,
            false
        );

        vm.startPrank(alice);

        // approve transfer
        burveV3.approve(address(burveV3), burnLiq);

        // check burn event
        vm.expectEmit(true, false, false, true);
        emit Burve.Burn(alice, burnLiq);

        // burn
        burveV3.burn(burnLiq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(
            burveV3.totalNominalLiq(),
            mintLiq - burnLiq,
            "total liq nominal"
        );

        // check shares
        assertEq(burveV3.totalShares(), mintLiq - burnLiq, "total shares");

        // check pool token balances
        assertGe(
            token0.balanceOf(address(alice)),
            burn0,
            "alice token0 balance"
        );
        assertGe(
            token1.balanceOf(address(alice)),
            burn1,
            "alice token1 balance"
        );

        // check burve LP token
        assertEq(
            burveV3.balanceOf(alice),
            mintLiq - burnLiq,
            "alice burve LP balance"
        );
    }

    function test_Burn_Full() public {
        uint128 mintLiq = 10_000;

        // Mint
        deal(address(token0), address(sender), type(uint256).max);
        deal(address(token1), address(sender), type(uint256).max);
        vm.startPrank(sender);
        token0.approve(address(burve), type(uint256).max);
        token1.approve(address(burve), type(uint256).max);
        burve.mint(address(alice), mintLiq, 0, type(uint128).max);
        vm.stopPrank();

        // Burn
        IKodiakIsland island = burve.island();

        // calc island burn
        uint128 islandBurnLiq = islandSharesToLiquidity(
            island,
            burve.islandSharesPerOwner(alice)
        );
        (uint256 islandBurn0, uint256 islandBurn1) = getAmountsForLiquidity(
            islandBurnLiq,
            island.lowerTick(),
            island.upperTick(),
            false
        );

        // calc v3 burn
        uint128 v3BurnLiq = uint128(shift96(mintLiq * burve.distX96(1), false));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Burn0, uint256 v3Burn1) = getAmountsForLiquidity(
            v3BurnLiq,
            lower,
            upper,
            false
        );

        uint256 burn0 = islandBurn0 + v3Burn0;
        uint256 burn1 = islandBurn1 + v3Burn1;

        vm.startPrank(alice);

        // approve transfer
        burve.approve(address(burve), mintLiq);

        // check burn event
        vm.expectEmit(true, false, false, true);
        emit Burve.Burn(alice, mintLiq);

        // burn
        burve.burn(mintLiq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burve.totalNominalLiq(), 0, "total liq nominal");

        // check shares
        assertEq(burve.totalShares(), 0, "total shares");

        // check pool token balances
        assertGe(
            token0.balanceOf(address(alice)),
            burn0,
            "alice token0 balance"
        );
        assertGe(
            token1.balanceOf(address(alice)),
            burn1,
            "alice token1 balance"
        );

        // check island LP token
        assertEq(
            burve.islandSharesPerOwner(alice),
            0,
            "alice islandSharesPerOwner balance"
        );
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(
            island.balanceOf(address(stationProxy)),
            0,
            "station proxy island LP balance"
        );

        // check burve LP token
        assertEq(burve.balanceOf(alice), 0, "alice burve LP balance");
    }

    function test_Burn_Partial() public {
        uint128 mintLiq = 10_000;
        uint128 burnLiq = 1_000;

        // Mint
        deal(address(token0), address(sender), type(uint256).max);
        deal(address(token1), address(sender), type(uint256).max);
        vm.startPrank(sender);
        token0.approve(address(burve), type(uint256).max);
        token1.approve(address(burve), type(uint256).max);
        burve.mint(address(alice), mintLiq, 0, type(uint128).max);
        vm.stopPrank();

        // Burn
        IKodiakIsland island = burve.island();

        // calc island burn
        uint256 islandShares = burve.islandSharesPerOwner(alice);
        uint256 burnIslandShares = FullMath.mulDiv(
            islandShares,
            burnLiq,
            mintLiq
        );

        uint128 islandBurnLiq = islandSharesToLiquidity(
            island,
            burnIslandShares
        );
        (uint256 islandBurn0, uint256 islandBurn1) = getAmountsForLiquidity(
            islandBurnLiq,
            island.lowerTick(),
            island.upperTick(),
            false
        );

        // calc v3 burn
        uint128 v3BurnLiq = uint128(shift96(burnLiq * burve.distX96(1), false));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Burn0, uint256 v3Burn1) = getAmountsForLiquidity(
            v3BurnLiq,
            lower,
            upper,
            false
        );

        uint256 burn0 = islandBurn0 + v3Burn0;
        uint256 burn1 = islandBurn1 + v3Burn1;

        vm.startPrank(alice);

        // approve transfer
        burve.approve(address(burve), burnLiq);

        // check burn event
        vm.expectEmit(true, false, false, true);
        emit Burve.Burn(alice, burnLiq);

        // burn
        burve.burn(burnLiq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(
            burve.totalNominalLiq(),
            mintLiq - burnLiq,
            "total liq nominal"
        );

        // check shares
        assertEq(burve.totalShares(), mintLiq - burnLiq, "total shares");

        // check pool token balances
        assertGe(
            token0.balanceOf(address(alice)),
            burn0,
            "alice token0 balance"
        );
        assertGe(
            token1.balanceOf(address(alice)),
            burn1,
            "alice token1 balance"
        );

        // check island LP token
        assertEq(
            burve.islandSharesPerOwner(alice),
            islandShares - burnIslandShares,
            "alice islandSharesPerOwner balance"
        );
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(
            island.balanceOf(address(stationProxy)),
            islandShares - burnIslandShares,
            "station proxy island LP balance"
        );

        // check burve LP token
        assertEq(
            burve.balanceOf(alice),
            mintLiq - burnLiq,
            "alice burve LP balance"
        );
    }

    function testRevert_Burn_SqrtPX96BelowLowerLimit() public {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 lowerSqrtPriceLimitX96 = sqrtRatioX96 + 100;
        uint160 upperSqrtPriceLimitX96 = sqrtRatioX96 + 200;
        vm.expectRevert(
            abi.encodeWithSelector(
                Burve.SqrtPriceX96OverLimit.selector,
                sqrtRatioX96,
                lowerSqrtPriceLimitX96,
                upperSqrtPriceLimitX96
            )
        );
        burve.burn(100, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96);
    }

    function testRevert_Burn_SqrtPX96AboveUpperLimit() public {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 lowerSqrtPriceLimitX96 = sqrtRatioX96 - 200;
        uint160 upperSqrtPriceLimitX96 = sqrtRatioX96 - 100;
        vm.expectRevert(
            abi.encodeWithSelector(
                Burve.SqrtPriceX96OverLimit.selector,
                sqrtRatioX96,
                lowerSqrtPriceLimitX96,
                upperSqrtPriceLimitX96
            )
        );
        burve.burn(100, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96);
    }

    // Compound Tests

    function test_CompoundV3Ranges_Single() public {
        uint256 collected0 = 10e18;
        uint256 collected1 = 10e18;

        // simulate collected amounts
        deal(address(token0), address(burve), collected0);
        deal(address(token1), address(burve), collected1);

        // compounded nominal liq
        uint128 compoundedNominalLiq = burve
            .collectAndCalcCompoundExposed();
        assertGt(compoundedNominalLiq, 0, "compoundedNominalLiq > 0");

        // v3 compounded liq
        uint128 v3CompoundedLiq = uint128(
            shift96(compoundedNominalLiq * burve.distX96(1), true)
        );
        (int24 v3Lower, int24 v3Upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsForLiquidity(
            v3CompoundedLiq,
            v3Lower,
            v3Upper,
            true
        );
        assertGt(v3CompoundedLiq, 0, "v3CompoundedLiq > 0");

        // check mint to v3 range
        vm.expectCall(
            address(pool),
            abi.encodeCall(
                pool.mint,
                (
                    address(burve),
                    v3Lower,
                    v3Upper,
                    v3CompoundedLiq,
                    abi.encode(address(burve))
                )
            )
        );

        burve.compoundV3RangesExposed();

        // check total nominal liq updated
        assertEq(
            burve.totalNominalLiq(),
            compoundedNominalLiq,
            "total nominal liq"
        );

        // check token transfer
        assertEq(
            token0.balanceOf(address(burve)),
            collected0 - v3Mint0,
            "burve token0 balance"
        );
        assertEq(
            token1.balanceOf(address(burve)),
            collected1 - v3Mint1,
            "burve token1 balance"
        );

        // check approvals
        assertEq(
            token0.allowance(address(burve), address(burve)),
            0,
            "token0 allowance"
        );
        assertEq(
            token1.allowance(address(burve), address(burve)),
            0,
            "token1 allowance"
        );
    }

    function test_CompoundV3Ranges_CompoundedNominalLiqIsZero() public {
        burve.compoundV3RangesExposed();
        assertEq(burve.totalNominalLiq(), 0, "total liq nominal");
    }

    function test_GetCompoundNominalLiqForCollectedAmounts_Collected0IsZero()
        public
    {
        // simulate collected amounts
        deal(address(token1), address(burve), 10e18);

        // verify assumptions about other parameters in equations
        (uint256 amount0InUnitLiqX64, ) = burve
            .getCompoundAmountsPerUnitNominalLiqX64Exposed();
        assertGt(amount0InUnitLiqX64, 0, "amount0InUnitLiqX64 > 0");

        // check compounded nominal liq
        uint128 compoundedNominalLiq = burve
            .collectAndCalcCompoundExposed();
        assertEq(compoundedNominalLiq, 0, "compoundedNominalLiq == 0");
    }

    function test_GetCompoundNominalLiqForCollectedAmounts_Collected1IsZero()
        public
    {
        // simulate collected amounts
        deal(address(token0), address(burve), 10e18);

        // verify assumptions about other parameters in equations
        (, uint256 amount1InUnitLiqX64) = burve
            .getCompoundAmountsPerUnitNominalLiqX64Exposed();
        assertGt(amount1InUnitLiqX64, 0, "amount1InUnitLiqX64 > 0");

        // check compounded nominal liq
        uint128 compoundedNominalLiq = burve
            .collectAndCalcCompoundExposed();
        assertEq(compoundedNominalLiq, 0, "compoundedNominalLiq == 0");
    }

    function test_GetCompoundNominalLiqForCollectedAmounts_Amount0InUnitLiqX64IsZero()
        public
    {
        // simulate collected amounts
        deal(address(token0), address(burve), 10e18);
        deal(address(token1), address(burve), 10e18);

        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.slot0.selector),
            abi.encode(TickMath.MAX_SQRT_RATIO, 0, 0, 0, 0, 0, true)
        );

        // verify assumptions about other parameters in equations
        (uint256 amount0InUnitLiqX64, uint256 amount1InUnitLiqX64) = burve
            .getCompoundAmountsPerUnitNominalLiqX64Exposed();
        assertEq(amount0InUnitLiqX64, 0, "amount0InUnitLiqX64 == 0");
        assertGt(amount1InUnitLiqX64, 0, "amount1InUnitLiqX64 > 0");

        // check compounded nominal liq
        uint128 compoundedNominalLiq = burve
            .collectAndCalcCompoundExposed();
        assertEq(compoundedNominalLiq, 0, "compoundedNominalLiq == 0");
    }

    function test_GetCompoundNominalLiqForCollectedAmounts_Amount1InUnitLiqX64IsZero()
        public
    {
        // simulate collected amounts
        deal(address(token0), address(burve), 10e18);
        deal(address(token1), address(burve), 10e18);

        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.slot0.selector),
            abi.encode(TickMath.MIN_SQRT_RATIO, 0, 0, 0, 0, 0, true)
        );

        // verify assumptions about other parameters in equations
        (uint256 amount0InUnitLiqX64, uint256 amount1InUnitLiqX64) = burve
            .getCompoundAmountsPerUnitNominalLiqX64Exposed();
        assertGt(amount0InUnitLiqX64, 0, "amount0InUnitLiqX64 > 0");
        assertEq(amount1InUnitLiqX64, 0, "amount1InUnitLiqX64 == 0");

        // check compounded nominal liq
        uint128 compoundedNominalLiq = burve
            .collectAndCalcCompoundExposed();
        assertEq(compoundedNominalLiq, 0, "compoundedNominalLiq == 0");
    }

    function test_GetCompoundNominalLiqForCollectedAmounts_NormalAmounts()
        public
    {
        // simulate collected amounts
        deal(address(token0), address(burve), 10e18);
        deal(address(token1), address(burve), 10e18);

        // verify assumptions about other parameters in equations
        (uint256 amount0InUnitLiqX64, uint256 amount1InUnitLiqX64) = burve
            .getCompoundAmountsPerUnitNominalLiqX64Exposed();
        assertGt(amount0InUnitLiqX64, 0, "amount0InUnitLiqX64 > 0");
        assertGt(amount1InUnitLiqX64, 0, "amount1InUnitLiqX64 > 0");

        // check compounded nominal liq
        uint128 compoundedNominalLiq = burve
            .collectAndCalcCompoundExposed();
        assertGt(compoundedNominalLiq, 0, "compoundedNominalLiq > 0");
    }

    function test_GetCompoundNominalLiqForCollectedAmounts_Extremes() public {
        // verify assumptions about other parameters in equations
        (uint256 amount0InUnitLiqX64, uint256 amount1InUnitLiqX64) = burve
            .getCompoundAmountsPerUnitNominalLiqX64Exposed();
        assertGt(amount0InUnitLiqX64, 0, "amount0InUnitLiqX64 > 0");
        assertGt(amount1InUnitLiqX64, 0, "amount1InUnitLiqX64 > 0");

        // amounts at capped max type(uint192).max
        deal(address(token0), address(burve), type(uint192).max);
        deal(address(token1), address(burve), type(uint192).max);

        uint128 compoundedNominalLiqAtMax192 = burve
            .collectAndCalcCompoundExposed();

        // amounts at max type(uint256).max
        deal(address(token0), address(burve), type(uint256).max);
        deal(address(token1), address(burve), type(uint256).max);

        uint128 compoundedNominalLiqAtMax256 = burve
            .collectAndCalcCompoundExposed();

        // check compounded nominal liq
        assertEq(
            compoundedNominalLiqAtMax192,
            compoundedNominalLiqAtMax256,
            "equal compounded nominal liq"
        );
        assertEq(
            compoundedNominalLiqAtMax192,
            type(uint128).max - 2,
            "equal max nominal liq"
        );
    }

    function test_GetCompoundAmountsPerUnitNominalLiqX64_CurrentSqrtP() public {
        // calc v3
        uint128 v3Liq = uint128(
            shift96(UNIT_NOMINAL_LIQ_X64 * burve.distX96(1), true)
        );
        (int24 v3Lower, int24 v3Upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsForLiquidity(
            v3Liq,
            v3Lower,
            v3Upper,
            true
        );

        // compound amounts
        (uint256 compound0, uint256 compound1) = burve
            .getCompoundAmountsPerUnitNominalLiqX64Exposed();

        assertEq(compound0, v3Mint0, "compount0 == v3Mint0");
        assertGt(compound0, 0, "compound0 > 0");
        assertEq(compound1, v3Mint1, "compound1 == v3Mint1");
        assertGt(compound1, 0, "compound0 > 0");
    }

    function test_GetCompoundAmountsPerUnitNominalLiqX64_MinSqrtP() public {
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.slot0.selector),
            abi.encode(TickMath.MIN_SQRT_RATIO, 0, 0, 0, 0, 0, true)
        );

        // calc v3
        uint128 v3Liq = uint128(
            shift96(UNIT_NOMINAL_LIQ_X64 * burve.distX96(1), true)
        );
        (int24 v3Lower, int24 v3Upper) = burve.ranges(1);
        (uint256 v3Mint0, ) = getAmountsForLiquidity(
            v3Liq,
            v3Lower,
            v3Upper,
            true
        );

        // compound amounts
        (uint256 compound0, uint256 compound1) = burve
            .getCompoundAmountsPerUnitNominalLiqX64Exposed();

        assertEq(compound0, v3Mint0, "compount0 == v3Mint0");
        assertGt(compound0, 0, "compound0 > 0");
        assertEq(compound1, 0, "compound1 == 0");
    }

    function test_GetCompoundAmountsPerUnitNominalLiqX64_MaxSqrtP() public {
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.slot0.selector),
            abi.encode(TickMath.MAX_SQRT_RATIO, 0, 0, 0, 0, 0, true)
        );

        // calc v3
        uint128 v3Liq = uint128(
            shift96(UNIT_NOMINAL_LIQ_X64 * burve.distX96(1), true)
        );
        (int24 v3Lower, int24 v3Upper) = burve.ranges(1);
        (, uint256 v3Mint1) = getAmountsForLiquidity(
            v3Liq,
            v3Lower,
            v3Upper,
            true
        );

        // compound amounts
        (uint256 compound0, uint256 compound1) = burve
            .getCompoundAmountsPerUnitNominalLiqX64Exposed();

        assertEq(compound0, 0, "compount0 == 0");
        assertEq(compound1, v3Mint1, "compound1 == v3Mint1");
        assertGt(compound1, 0, "compound1 > 0");
    }

    function test_CollectV3Fees() public forkOnly {
        (int24 lower, int24 upper) = burveV3.ranges(0);
        vm.expectCall(
            address(pool),
            abi.encodeCall(
                pool.collect,
                (
                    address(burveV3),
                    lower,
                    upper,
                    type(uint128).max,
                    type(uint128).max
                )
            )
        );
        burveV3.collectV3FeesExposed();
    }

    // Helpers

    /// @notice Gets the current tick clamped to respect the tick spacing
    function getClampedCurrentTick() internal view returns (int24) {
        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        return currentTick - (currentTick % tickSpacing);
    }

    /// @notice Calculate token amounts in liquidity for the given range.
    /// @param liquidity The amount of liquidity.
    /// @param lower The lower tick of the range.
    /// @param upper The upper tick of the range.
    function getAmountsForLiquidity(
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

    /// @notice Calculates the liquidity represented by island shares
    /// @param island The island
    /// @param shares The shares
    /// @return liquidity The liquidity
    function islandSharesToLiquidity(
        IKodiakIsland island,
        uint256 shares
    ) internal view returns (uint128 liquidity) {
        bytes32 positionId = island.getPositionID();
        (uint128 poolLiquidity, , , , ) = pool.positions(positionId);
        uint256 totalSupply = island.totalSupply();
        liquidity = uint128(
            FullMath.mulDiv(shares, poolLiquidity, totalSupply)
        );
    }

    function shift96(
        uint256 a,
        bool roundUp
    ) internal pure returns (uint256 b) {
        b = a >> 96;
        if (roundUp && (a & X96_MASK) > 0) b += 1;
    }
}
