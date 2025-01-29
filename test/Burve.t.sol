// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Burve} from "../src/Burve.sol";
import {BartioAddresses} from "./utils/BaritoAddresses.sol";
import {IKodiakIsland} from "../src/integrations/kodiak/IKodiakIsland.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiquidityAmounts} from "../src/integrations/uniswap/LiquidityAmounts.sol";
import {TickMath} from "../src/integrations/uniswap/TickMath.sol";

contract BurveTest is Test {
    Burve public burve;

    function setUp() public {}

    function testBasic() public {}

    function testIsland() public {
        address me = address(0x0); // replace with your address
        vm.startPrank(me);

        IKodiakIsland island = IKodiakIsland(
            BartioAddresses.KODIAK_BERA_YEET_ISLAND_NEW
        );

        // TODO(Austin): Not working? Improper setup?
        uint256 balance0 = island.token0().balanceOf(me);
        uint256 balance1 = island.token1().balanceOf(me);

        (uint160 sqrtRatioX96, , , , , , ) = island.pool().slot0();

        uint128 calcLiq = getLiquidityForAmounts(
            sqrtRatioX96,
            island.lowerTick(),
            island.upperTick(),
            balance0,
            balance1
        );

        (uint256 mint0, uint256 mint1) = getAmountsFromLiquidity(
            sqrtRatioX96,
            island.lowerTick(),
            island.upperTick(),
            calcLiq,
            false
        );

        (uint256 transfer0, uint256 transfer1, uint256 mintedAmount) = island
            .getMintAmounts(balance0, balance1);
        assert(transfer0 <= balance0);
        assert(transfer1 <= balance1);

        island.token0().approve(address(island), transfer0);
        island.token1().approve(address(island), transfer1);

        (, , uint128 liqMinted) = island.mint(mintedAmount, me);

        assertEq(liqMinted, calcLiq);

        vm.stopPrank();
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
