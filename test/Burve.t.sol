// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ForkableTest} from "@Commons/Test/ForkableTest.sol";

import { BartioAddresses } from "./utils/BaritoAddresses.sol";
import { Burve, TickRange } from "../src/Burve.sol";
import { IKodiakIsland } from "../src/integrations/kodiak/IKodiakIsland.sol";
import { IUniswapV3Pool } from "../src/integrations/kodiak/IUniswapV3Pool.sol";
import { LiquidityAmounts } from "../src/integrations/uniswap/LiquidityAmounts.sol";
import { TickMath } from "../src/integrations/uniswap/TickMath.sol";

contract BurveTest is ForkableTest {
    Burve public burveIsland; // island only
    Burve public burveV3; // v3 only
    Burve public burve; // island + v3

    IUniswapV3Pool pool;
    IERC20 token0;
    IERC20 token1;

    address alice;

    uint256 private constant X96MASK = (1 << 96) - 1;

    function forkSetup() internal virtual override {
        alice = makeAddr('Alice');

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

    // Mint Tests

    function testIslandMintSenderIsRecipient() public {
        uint128 liq = 10_000;

        (uint256 mint0, uint256 mint1, uint256 mintShares) = getMintAmountsFromIslandLiquidity(burveIsland.island(), liq);

        deal(address(token0), address(alice), mint0);
        deal(address(token1), address(alice), mint1);

        vm.startPrank(alice);

        token0.approve(address(burveIsland), mint0);
        token1.approve(address(burveIsland), mint1);

        burveIsland.mint(address(alice), liq);

        vm.stopPrank();

        assertEq(token0.balanceOf(address(alice)), 0, "alice token0 balance");
        assertEq(token1.balanceOf(address(alice)), 0, "alice token1 balance");
        assertEq(
            IERC20(burveIsland.island()).balanceOf(alice),
            mintShares,
            "alice island LP balance"
        );
        assertEq(
            IERC20(burveIsland).balanceOf(alice),
            liq,
            "alice burve LP balance"
        );
    }

    function testIslandMintSenderNotRecipient() public {
        address sender = address(this);
        uint128 liq = 10_000;

        (uint256 mint0, uint256 mint1, uint256 mintShares) = getMintAmountsFromIslandLiquidity(burveIsland.island(), liq);

        deal(address(token0), sender, mint0);
        deal(address(token1), sender, mint1);

        token0.approve(address(burveIsland), mint0);
        token1.approve(address(burveIsland), mint1);

        burveIsland.mint(address(alice), liq);

        assertEq(token0.balanceOf(address(sender)), 0, "sender token0 balance");
        assertEq(token1.balanceOf(address(sender)), 0, "sender token1 balance");
        assertEq(
            IERC20(burveIsland.island()).balanceOf(alice),
            mintShares,
            "alice island LP balance"
        );
        assertEq(
            IERC20(burveIsland).balanceOf(alice),
            liq,
            "alice burve LP balance"
        );
    }

    function testV3MintSenderIsRecipient() public {
        uint128 liq = 10_000;

        (int24 lower, int24 upper) = burveV3.ranges(0);
        (uint256 mint0, uint256 mint1) = getAmountsFromLiquidity(liq, lower, upper, true);

        deal(address(token0), address(alice), mint0);
        deal(address(token1), address(alice), mint1);

        vm.startPrank(alice);

        token0.approve(address(burveV3), mint0);
        token1.approve(address(burveV3), mint1);

        burveV3.mint(address(alice), liq);

        vm.stopPrank();

        assertEq(token0.balanceOf(address(alice)), 0, "alice token0 balance");
        assertEq(token1.balanceOf(address(alice)), 0, "alice token1 balance");
        assertEq(
            IERC20(burveV3).balanceOf(alice),
            liq,
            "alice burve LP balance"
        );
    }

    function testV3MintSenderNotRecipient() public {
        address sender = address(this);
        uint128 liq = 10_000;

        (int24 lower, int24 upper) = burveV3.ranges(0);
        (uint256 mint0, uint256 mint1) = getAmountsFromLiquidity(liq, lower, upper, true);

        deal(address(token0), address(sender), mint0);
        deal(address(token1), address(sender), mint1);

        token0.approve(address(burveV3), mint0);
        token1.approve(address(burveV3), mint1);

        burveV3.mint(address(alice), liq);

        assertEq(token0.balanceOf(address(sender)), 0, "sende token0 balance");
        assertEq(token1.balanceOf(address(sender)), 0, "sende token1 balance");
        assertEq(
            IERC20(burveV3).balanceOf(alice),
            liq,
            "alice burve LP balance"
        );
    }

    function testMintSenderIsRecipient() public {
        uint128 liq = 10_000;

        // island liq
        uint128 islandLiq = uint128(shift96(liq * burve.distX96(0), true));
        (uint256 islandMint0, uint256 islandMint1, uint256 islandMintShares) = getMintAmountsFromIslandLiquidity(burve.island(), islandLiq);

        // v3 liq
        uint128 v3Liq = uint128(shift96(liq * burve.distX96(1), true));
        (int24 lower, int24 upper) = burve.ranges(1);
        (uint256 v3Mint0, uint256 v3Mint1) = getAmountsFromLiquidity(v3Liq, lower, upper, true);

        uint256 mint0 = islandMint0 + v3Mint0;
        uint256 mint1 = islandMint1 + v3Mint1;

        deal(address(token0), address(alice), mint0);
        deal(address(token1), address(alice), mint1);

        vm.startPrank(alice);

        token0.approve(address(burve), mint0);
        token1.approve(address(burve), mint1);

        burve.mint(address(alice), liq);

        vm.stopPrank();

        assertEq(token0.balanceOf(address(alice)), 0, "alice token0 balance");
        assertEq(token1.balanceOf(address(alice)), 0, "alice token1 balance");
        assertEq(
            IERC20(burve.island()).balanceOf(alice),
            islandMintShares,
            "alice island LP balance"
        );
        assertEq(
            IERC20(burve).balanceOf(alice),
            liq,
            "alice burve LP balance"
        );
    }

    function testMintSenderNotRecipient() public {
        address sender = address(this);
        uint128 liq = 10_000;

        // island liq
        uint128 islandLiq = uint128(shift96(liq * burve.distX96(0), true));
        (uint256 islandMint0, uint256 islandMint1, uint256 islandMintShares) = getMintAmountsFromIslandLiquidity(burve.island(), islandLiq);

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

        burve.mint(address(alice), liq);

        assertEq(token0.balanceOf(address(sender)), 0, "sender token0 balance");
        assertEq(token1.balanceOf(address(sender)), 0, "sender token1 balance");
        assertEq(
            IERC20(burve.island()).balanceOf(alice),
            islandMintShares,
            "alice island LP balance"
        );
        assertEq(
            IERC20(burve).balanceOf(alice),
            liq,
            "alice burve LP balance"
        );
    }

    function testUniswapV3MintCallback() public {
        uint256 priorPoolBalance0 = token0.balanceOf(address(pool));
        uint256 priorPoolBalance1 = token1.balanceOf(address(pool));

        uint256 amount0Owed = 1e18;
        uint256 amount1Owed = 2e18;

        // deal tokens to Alice
        deal(address(token0), address(alice), amount0Owed);
        deal(address(token1), address(alice), amount1Owed);

        assertEq(token0.balanceOf(alice), amount0Owed, "alice starting token0 balance");
        assertEq(token1.balanceOf(alice), amount1Owed, "alice starting token0 balance");

        // approve tokens for transfer from Burve
        vm.startPrank(alice);
        token0.approve(address(burveV3), amount0Owed);
        token1.approve(address(burveV3), amount1Owed);
        vm.stopPrank();

        // call uniswapV3MintCallback
        vm.prank(address(pool));
        burveV3.uniswapV3MintCallback(amount0Owed, amount1Owed, abi.encode(alice));

        assertEq(token0.balanceOf(alice), 0, "alice ending token0 balance");
        assertEq(token1.balanceOf(alice), 0, "alice ending token0 balance");

        uint256 postPoolBalance0 = token0.balanceOf(address(pool));
        uint256 postPoolBalance1 = token1.balanceOf(address(pool));

        assertEq(postPoolBalance0 - priorPoolBalance0, amount0Owed, "pool received token0 balance");
        assertEq(postPoolBalance1 - priorPoolBalance1, amount1Owed, "pool received token1 balance");
    }

    function testRevertUniswapV3MintCallbackSenderNotPool() public {
        vm.expectRevert(abi.encodeWithSelector(Burve.UniswapV3MintCallbackSenderNotPool.selector, address(this)));
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

    function shift96(
        uint256 a,
        bool roundUp
    ) internal pure returns (uint256 b) {
        b = a >> 96;
        if (roundUp && (a & X96MASK) > 0) b += 1;
    }
}
