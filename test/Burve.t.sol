// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Test, console } from "forge-std/Test.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ForkableTest } from "@Commons/Test/ForkableTest.sol";

import { BartioAddresses } from "./utils/BaritoAddresses.sol";
import { Burve, TickRange } from "../src/Burve.sol";
import { FullMath } from "../src/multi/FullMath.sol";
import { IKodiakIsland } from "../src/integrations/kodiak/IKodiakIsland.sol";
import { IStationProxy } from "../src/IStationProxy.sol";
import { IUniswapV3Pool } from "../src/integrations/kodiak/IUniswapV3Pool.sol";
import { LiquidityAmounts } from "../src/integrations/uniswap/LiquidityAmounts.sol";
import { NullStationProxy } from "./NullStationProxy.sol";
import { TickMath } from "../src/integrations/uniswap/TickMath.sol";

contract BurveTest is ForkableTest {
    Burve public burve; // island + v3

    IUniswapV3Pool pool;
    IERC20 token0;
    IERC20 token1;

    IStationProxy stationProxy;

    address alice;
    address sender;

    uint256 private constant X96MASK = (1 << 96) - 1;

    function forkSetup() internal virtual override {
        alice = makeAddr('Alice');
        sender = makeAddr('Sender');

        stationProxy = new NullStationProxy();

        // Pool info
        pool = IUniswapV3Pool(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3
        );
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        int24 tickSpacing = pool.tickSpacing();
        int24 clampedCurrentTick = getClampedCurrentTick();

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

    // Constructor Tests 

    function testRevertCreateNoV3Range() public {
        vm.expectRevert(Burve.InsufficientRanges.selector);
        burve = new Burve(
            BartioAddresses.KODIAK_HONEY_NECT_POOL_V3,
            BartioAddresses.KODIAK_HONEY_NECT_ISLAND,
            address(stationProxy),
            new TickRange[](0),
            new uint128[](0)
        );
    }

    // Mint Tests 

    function testMintSenderIsRecipient() public {
        uint128 liq = 10_000;
        IKodiakIsland island = burve.island();

        // calc island mint
        uint128 islandLiq = uint128(shift96(liq * burve.islandV3DistX96(0), true));
        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(islandLiq, island.lowerTick(), island.upperTick(), false);
        (uint256 islandMint0, uint256 islandMint1, uint256 islandMintShares) = island.getMintAmounts(amount0, amount1);

        // calc v3 mint
        uint128 v3Liq = uint128(shift96(liq * burve.islandV3DistX96(1), true));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsForLiquidity(v3Liq, lower, upper, true);

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

        burve.mint(address(alice), liq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burve.totalV3Liq(), v3Liq, "total v3 liq");

        // check shares
        assertEq(burve.totalShares(), v3Liq, "total shares");

        // check pool token balances
        assertEq(token0.balanceOf(address(alice)), 0, "alice token0 balance");
        assertEq(token1.balanceOf(address(alice)), 0, "alice token1 balance");

        // check island LP token
        assertEq(burve.islandSharesPerOwner(alice), islandMintShares, "alice islandSharesPerOwner balance");
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(island.balanceOf(address(stationProxy)), islandMintShares, "station proxy island LP balance");

        // check burve LP token
        assertEq(burve.balanceOf(alice), v3Liq, "alice burve LP balance");
    }

    function testMintSenderNotRecipient() public {
        uint128 liq = 10_000;
        IKodiakIsland island = burve.island();

        // calc island mint
        uint128 islandLiq = uint128(shift96(liq * burve.islandV3DistX96(0), true));
        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(islandLiq, island.lowerTick(), island.upperTick(), false);
        (uint256 islandMint0, uint256 islandMint1, uint256 islandMintShares) = island.getMintAmounts(amount0, amount1);

        // calc v3 mint
        uint128 v3Liq = uint128(shift96(liq * burve.islandV3DistX96(1), true));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsForLiquidity(v3Liq, lower, upper, true);

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

        burve.mint(address(alice), liq, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burve.totalV3Liq(), v3Liq, "total v3 liq");

        // check shares
        assertEq(burve.totalShares(), v3Liq, "total shares");

        // check pool token balances
        assertEq(token0.balanceOf(address(sender)), 0, "sender token0 balance");
        assertEq(token1.balanceOf(address(sender)), 0, "sender token1 balance");

        // check island LP token
        assertEq(burve.islandSharesPerOwner(alice), islandMintShares, "alice islandSharesPerOwner balance");
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(island.balanceOf(address(stationProxy)), islandMintShares, "station proxy island LP balance");

        // check burve LP token
        assertEq(burve.balanceOf(alice), v3Liq, "alice burve LP balance");
    }

    function testUniswapV3MintCallback() public {
        uint256 priorPoolBalance0 = token0.balanceOf(address(pool));
        uint256 priorPoolBalance1 = token1.balanceOf(address(pool));

        uint256 amount0Owed = 1e18;
        uint256 amount1Owed = 2e18;

        // deal required tokens
        deal(address(token0), address(alice), amount0Owed);
        deal(address(token1), address(alice), amount1Owed);

        assertEq(token0.balanceOf(alice), amount0Owed, "alice starting token0 balance");
        assertEq(token1.balanceOf(alice), amount1Owed, "alice starting token0 balance");

        // approve transfer
        vm.startPrank(alice);
        token0.approve(address(burve), amount0Owed);
        token1.approve(address(burve), amount1Owed);
        vm.stopPrank();

        // call uniswapV3MintCallback
        vm.prank(address(pool));
        burve.uniswapV3MintCallback(amount0Owed, amount1Owed, abi.encode(alice));

        assertEq(token0.balanceOf(alice), 0, "alice ending token0 balance");
        assertEq(token1.balanceOf(alice), 0, "alice ending token0 balance");

        uint256 postPoolBalance0 = token0.balanceOf(address(pool));
        uint256 postPoolBalance1 = token1.balanceOf(address(pool));

        assertEq(postPoolBalance0 - priorPoolBalance0, amount0Owed, "pool received token0 balance");
        assertEq(postPoolBalance1 - priorPoolBalance1, amount1Owed, "pool received token1 balance");
    }

    function testRevertUniswapV3MintCallbackSenderNotPool() public {
        vm.expectRevert(abi.encodeWithSelector(Burve.UniswapV3MintCallbackSenderNotPool.selector, address(this)));
        burve.uniswapV3MintCallback(0, 0, abi.encode(address(this)));
    }

    function testRevertMintSqrtPX96BelowLowerLimit() public {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 lowerSqrtPriceLimitX96 = sqrtRatioX96 + 100;
        uint160 upperSqrtPriceLimitX96 = sqrtRatioX96 + 200;
        vm.expectRevert(abi.encodeWithSelector(Burve.SqrtPriceX96OverLimit.selector, sqrtRatioX96, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96));
        burve.mint(address(alice), 100, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96);
    }

    function testRevertMintSqrtPX96AboveUpperLimit() public {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 lowerSqrtPriceLimitX96 = sqrtRatioX96 - 200;
        uint160 upperSqrtPriceLimitX96 = sqrtRatioX96 - 100;
        vm.expectRevert(abi.encodeWithSelector(Burve.SqrtPriceX96OverLimit.selector, sqrtRatioX96, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96));
        burve.mint(address(alice), 100, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96);
    }

    // Burn Tests

    function testBurnFull() public {
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

        uint256 burnShares = burve.balanceOf(alice);
        
        // calc island burn
        uint128 islandBurnLiq = islandSharesToLiquidity(island, burve.islandSharesPerOwner(alice));
        (uint256 islandBurn0, uint256 islandBurn1) = getAmountsForLiquidity(islandBurnLiq, island.lowerTick(), island.upperTick(), false);

        // calc v3 burn
        uint128 v3BurnLiq = uint128(shift96(burve.totalV3Liq() * burve.v3DistX96(1), false));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Burn0, uint256 v3Burn1) = getAmountsForLiquidity(v3BurnLiq, lower, upper, false);

        uint256 burn0 = islandBurn0 + v3Burn0;
        uint256 burn1 = islandBurn1 + v3Burn1;

        vm.startPrank(alice);

        // approve transfer
        burve.approve(address(burve), burnShares);

        burve.burn(burnShares, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burve.totalV3Liq(), 0, "total liq nominal");

        // check shares
        assertEq(burve.totalShares(), 0, "total shares");

        // check pool token balances
        assertGe(token0.balanceOf(address(alice)), burn0, "alice token0 balance");
        assertGe(token1.balanceOf(address(alice)), burn1, "alice token1 balance");

        // check island LP token
        assertEq(burve.islandSharesPerOwner(alice), 0, "alice islandSharesPerOwner balance");
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(island.balanceOf(address(stationProxy)), 0, "station proxy island LP balance");

        // check burve LP token
        assertEq(burve.balanceOf(alice), 0, "alice burve LP balance");
    }

    function testBurnPartial() public {
        uint128 mintLiq = 10_000;

        // Mint
        deal(address(token0), address(sender), type(uint256).max);
        deal(address(token1), address(sender), type(uint256).max);
        vm.startPrank(sender);
        token0.approve(address(burve), type(uint256).max);
        token1.approve(address(burve), type(uint256).max);
        burve.mint(address(alice), mintLiq, 0, type(uint128).max);
        vm.stopPrank();

        uint256 mintedTotalV3Liq = burve.totalV3Liq();
        uint256 mintedIslandShares = burve.islandSharesPerOwner(alice);

        // Burn 20%
        IKodiakIsland island = burve.island();

        uint256 shares = burve.balanceOf(alice);
        uint256 burnShares = FullMath.mulDiv(shares, 20, 100);

        // calc island burn
        uint256 islandBurnShares = FullMath.mulDiv(burve.islandSharesPerOwner(alice), 20, 100);
        uint128 islandBurnLiq = islandSharesToLiquidity(island, islandBurnShares);
        (uint256 islandBurn0, uint256 islandBurn1) = getAmountsForLiquidity(islandBurnLiq, island.lowerTick(), island.upperTick(), false);

        // calc v3 burn
        uint128 burnTotalV3Liq = uint128(FullMath.mulDiv(burnShares, burve.totalV3Liq(), burve.totalShares()));
        uint128 v3BurnLiq = uint128(shift96(burnTotalV3Liq * burve.v3DistX96(1), false));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Burn0, uint256 v3Burn1) = getAmountsForLiquidity(v3BurnLiq, lower, upper, false);

        uint256 burn0 = islandBurn0 + v3Burn0;
        uint256 burn1 = islandBurn1 + v3Burn1;

        vm.startPrank(alice);

        // approve transfer
        burve.approve(address(burve), burnShares);

        burve.burn(burnShares, 0, type(uint128).max);

        vm.stopPrank();

        // check liq
        assertEq(burve.totalV3Liq(), mintedTotalV3Liq - burnTotalV3Liq, "total liq nominal");

        // check shares
        assertEq(burve.totalShares(), shares - burnShares, "total shares");

        // check pool token balances
        assertGe(token0.balanceOf(address(alice)), burn0, "alice token0 balance");
        assertGe(token1.balanceOf(address(alice)), burn1, "alice token1 balance");

        // check island LP token
        assertEq(burve.islandSharesPerOwner(alice), mintedIslandShares - islandBurnShares, "alice islandSharesPerOwner balance");
        assertEq(island.balanceOf(alice), 0, "alice island LP balance");
        assertEq(island.balanceOf(address(stationProxy)), mintedIslandShares - islandBurnShares, "station proxy island LP balance");

        // check burve LP token
        assertEq(burve.balanceOf(alice), shares - burnShares, "alice burve LP balance");
    }

    function testRevertBurnSqrtPX96BelowLowerLimit() public {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 lowerSqrtPriceLimitX96 = sqrtRatioX96 + 100;
        uint160 upperSqrtPriceLimitX96 = sqrtRatioX96 + 200;
        vm.expectRevert(abi.encodeWithSelector(Burve.SqrtPriceX96OverLimit.selector, sqrtRatioX96, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96));
        burve.burn(100, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96);
    }

    function testRevertBurnSqrtPX96AboveUpperLimit() public {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 lowerSqrtPriceLimitX96 = sqrtRatioX96 - 200;
        uint160 upperSqrtPriceLimitX96 = sqrtRatioX96 - 100;
        vm.expectRevert(abi.encodeWithSelector(Burve.SqrtPriceX96OverLimit.selector, sqrtRatioX96, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96));
        burve.burn(100, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96);
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
    function islandSharesToLiquidity(IKodiakIsland island, uint256 shares) internal view returns (uint128 liquidity) {
        bytes32 positionId = island.getPositionID();
        (uint128 poolLiquidity,,,,) = pool.positions(positionId);
        uint256 totalSupply = island.totalSupply();
        liquidity = uint128(FullMath.mulDiv(shares, poolLiquidity, totalSupply));
    }

    function shift96(
        uint256 a,
        bool roundUp
    ) internal pure returns (uint256 b) {
        b = a >> 96;
        if (roundUp && (a & X96MASK) > 0) b += 1;
    }
}
