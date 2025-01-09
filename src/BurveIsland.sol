// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import {IUniswapV3Pool} from "./integrations/kodiak/IUniswapV3Pool.sol";
// import {TransferHelper} from "./TransferHelper.sol";

// import { IKodiakIsland } from "./integrations/kodiak/IKodiakIsland.sol";

// contract BurveIsland is ERC20 {

//     IKodiakIsland public island;
//     IUniswapV3Pool public pool;

//     constructor(
//         address _island,
//         uint128 _islandWeight,
//         TickRange[] memory _ranges,
//         uint128[] memory _weights
//     ) ERC20(get_name(_pool), get_symbol(_pool)) {
//         island = IKodiakIsland(_island);

//         for (uint256 i = 0; i < _ranges.length; ++i) {
//             ranges.push(_ranges[i]);
//         }

//         uint256 sum = _islandWeight;
//         for (uint256 i = 0; i < _weights.length; ++i) {
//             sum += _weights[i];
//         }

//         for (uint256 i = 0; i < _weights.length; ++i) {
//             distX96.push((_weights[i] << 96) / sum);
//         }
//     }

//     function addLiq(uint128 liq) external {
//         // split liq
//         uint128 islandLiq = liq;

//         (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
//         (uint256 islandAmount0, uint256 islandAmount1) = getAmountsFromLiquidity(
//             sqrtRatioX96,
//             island.lowerTick(),
//             island.upperTick(),
//             islandLiq,
//             false
//         );

//         (,, uint256 mintAmount) = island.getMintAmounts(islandAmount0, islandAmount1);
//         island.mint(mintAmount, msg.sender);

//     }

//     /* Callbacks */

//     function uniswapV3MintCallback(
//         uint256 amount0Owed,
//         uint256 amount1Owed,
//         bytes calldata data
//     ) external {
//         address source = abi.decode(data, (address));
//         TransferHelper.safeTransferFrom(
//             token0,
//             source,
//             address(innerPool),
//             amount0Owed
//         );
//         TransferHelper.safeTransferFrom(
//             token1,
//             source,
//             address(innerPool),
//             amount1Owed
//         );
//     }

//     /* internal helpers */

//     function shift96(
//         uint256 a,
//         bool roundUp
//     ) internal pure returns (uint256 b) {
//         b = a >> 96;
//         if (roundUp && (a & X96MASK) > 0) b += 1;
//     }

//         /**
//      * @notice helper function to convert amounts of token0 / token1 to
//      * a liquidity value
//      * @param sqrtRatioX96 price from slot0
//      * @param tickLower bound
//      * @param tickUpper bound
//      * @param amount0Desired max amount0 available for minting
//      * @param amount1Desired max amount1 available for minting
//      */
//     function getLiquidityForAmounts(
//         uint160 sqrtRatioX96,
//         int24 tickLower,
//         int24 tickUpper,
//         uint256 amount0Desired,
//         uint256 amount1Desired
//     ) internal pure returns (uint128 liquidity) {
//         uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
//         uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
//         liquidity = LiquidityAmounts.getLiquidityForAmounts(
//             sqrtRatioX96,
//             sqrtRatioAX96,
//             sqrtRatioBX96,
//             amount0Desired,
//             amount1Desired
//         );
//     }

//     /**
//      * @notice helper function to convert the amount of liquidity to
//      * amount0 and amount1
//      * @param sqrtRatioX96 price from slot0
//      * @param tickLower bound
//      * @param tickUpper bound
//      * @param liquidity to find amounts for
//      * @param roundUp round amounts up
//      */
//     function getAmountsFromLiquidity(
//         uint160 sqrtRatioX96,
//         int24 tickLower,
//         int24 tickUpper,
//         uint128 liquidity,
//         bool roundUp
//     ) internal pure returns (uint256 amount0, uint256 amount1) {
//         uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
//         uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
//         (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
//             sqrtRatioX96,
//             sqrtRatioAX96,
//             sqrtRatioBX96,
//             liquidity,
//             roundUp
//         );
//     }

//     function get_name(address _island) private view returns (string memory name) {
//         IERC20 t0 = IKodiakIsland(_island).token0();
//         IERC20 t1 = IKodiakIsland(_island).token1();
//         name = string.concat(
//             t0.name(),
//             "-",
//             t1.name(),
//             "-Stable-KodiakLP"
//         );
//     }

//     function get_symbol(address _island) private view returns (string memory sym) {
//         IERC20 t0 = IKodiakIsland(_island).token0();
//         IERC20 t1 = IKodiakIsland(_island).token1();
//         sym = string.concat(
//             t0.symbol(),
//             "-",
//             t1.symbol(),
//             "-SLP-KDK"
//         );
//     }
// }
