// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV3Pool} from "./integrations/kodiak/IUniswapV3Pool.sol";
import {TransferHelper} from "./../TransferHelper.sol";
import {IKodiakIsland} from "./integrations/kodiak/IKodiakIsland.sol";
import {LiquidityAmounts} from "./integrations/uniswap/LiquidityAmounts.sol";
import {TickMath} from "./integrations/uniswap/TickMath.sol";

using TickRangeImpl for TickRange global;

struct Info {
    address pool;
    address island;
    TickRange[] ranges;
    uint256[] distX96;
}

/// Defines the tick range of an AMM position.
struct TickRange {
    /// Lower tick of the range.
    int24 lower;
    /// Upper tick of the range.
    int24 upper;
}

/// Implementation library for TickRange.
library TickRangeImpl {
    /// @notice Checks whether the given range is encoded to represent the island.
    /// @param range The range to check.
    /// @return isIsland True if the range is for an island.
    function isIsland(TickRange memory range) internal pure returns (bool) {
        return range.lower == 0 && range.upper == 0;
    }
}

contract Burve is ERC20 {
    IKodiakIsland public island;

    IUniswapV3Pool public pool;
    address public token0;
    address public token1;

    /// The n ranges.
    TickRange[] public ranges;

    /// The relative liquidity for our n ranges.
    /// If there is an island that distribution lies at index 0.
    uint256[] public distX96;

    uint256 private constant X96MASK = (1 << 96) - 1;

    /// Thrown when island specific logic is invoked but the contract was not initialized with an island.
    error NoIsland();

    /// Thrown when the provided island points to a pool that does not match the provided pool.
    error MismatchedIslandPool(address island, address pool);

    /// Thrown in the consturctor if the supplied pool address is the zero address.
    error PoolIsZeroAddress();

    /// Thrown when the number of ranges and number of weights do not match.
    error MismatchedRangeWeightLengths(
        uint256 rangeLength,
        uint256 weightLength
    );

    /// Thrown if the given tick range does not match the pools tick spacing.
    error InvalidRange(int24 lower, int24 upper);

    /// If you burn too much liq at once, we can't collect that amount in one call.
    /// Please split up into multiple calls.
    error TooMuchBurnedAtOnce(uint128 liq, uint256 tokens, bool isX);

    /// @param _pool The pool we are wrapping
    /// @param _island The optional island we are wrapping
    /// @param _ranges the n ranges
    /// @param _weights n weights defining the relative liquidity for each range.
    constructor(
        address _pool,
        address _island,
        TickRange[] memory _ranges,
        uint128[] memory _weights
    ) ERC20(nameFromPool(_pool), symbolFromPool(_pool)) {
        pool = IUniswapV3Pool(_pool);
        token0 = pool.token0();
        token1 = pool.token1();

        island = IKodiakIsland(_island);

        if (_pool == address(0x0)) {
            revert PoolIsZeroAddress();
        }

        if (_island != address(0x0) && address(island.pool()) != _pool) {
            revert MismatchedIslandPool(_island, _pool);
        }

        if (_ranges.length != _weights.length) {
            revert MismatchedRangeWeightLengths(
                _ranges.length,
                _weights.length
            );
        }

        int24 tickSpacing = pool.tickSpacing();

        // copy ranges to storage
        for (uint256 i = 0; i < _ranges.length; ++i) {
            TickRange memory range = _ranges[i];

            ranges.push(range);

            if (range.isIsland() && address(island) == address(0x0)) {
                revert NoIsland();
            }

            if (
                (range.lower % tickSpacing != 0) ||
                (range.upper % tickSpacing != 0)
            ) {
                revert InvalidRange(range.lower, range.upper);
            }
        }

        // compute total sum of weights
        uint256 sum = 0;
        for (uint256 i = 0; i < _weights.length; ++i) {
            sum += _weights[i];
        }

        // calculate distribution for each weighted position
        for (uint256 i = 0; i < _weights.length; ++i) {
            distX96.push((_weights[i] << 96) / sum);
        }
    }

    /// @notice mints liquidity for the recipient
    function mint(address recipient, uint128 liq) external {
        for (uint256 i = 0; i < distX96.length; ++i) {
            uint128 liqAmount = uint128(shift96(liq * distX96[i], true));
            mintRange(ranges[i], recipient, liqAmount);
        }

        _mint(recipient, liq);
    }

    /// @notice Helper method for minting to the given range.
    /// Used to decipher between the island and v3 ranges.
    /// @param range The range to mint to.
    /// @param recipient The recipient of the minted liquidity.
    /// @param liq The amount of liquidity to mint.
    function mintRange(
        TickRange memory range,
        address recipient,
        uint128 liq
    ) internal {
        // mint the island
        if (range.lower == 0 && range.upper == 0) {
            uint256 mintShares = islandLiqToShares(liq);
            island.mint(mintShares, recipient);
        } else {
            // mint the V3 ranges
            pool.mint(
                address(this),
                range.lower,
                range.upper,
                liq,
                abi.encode(msg.sender)
            );
        }
    }

    /// @notice burns liquidity for the msg.sender
    function burn(uint128 liq) external {
        _burn(msg.sender, liq);

        for (uint256 i = 0; i < distX96.length; ++i) {
            uint128 liqAmount = uint128(shift96(liq * distX96[i], true));
            burnRange(ranges[i], liqAmount);
        }
    }

    /// @notice Helper method for burning from the given range.
    /// Used to decipher between the island and v3 ranges.
    /// @param range The range to burn from.
    /// @param liq The amount of liquidity to burn.
    function burnRange(TickRange memory range, uint128 liq) internal {
        if (range.lower == 0 && range.upper == 0) {
            uint256 burnShares = islandLiqToShares(liq);
            island.burn(burnShares, msg.sender);
        } else {
            (uint256 x, uint256 y) = pool.burn(range.lower, range.upper, liq);

            if (x > type(uint128).max) revert TooMuchBurnedAtOnce(liq, x, true);
            if (y > type(uint128).max)
                revert TooMuchBurnedAtOnce(liq, y, false);

            pool.collect(
                msg.sender,
                range.lower,
                range.upper,
                uint128(x),
                uint128(y)
            );
        }
    }

    /// @notice Gets info about the contract.
    /// @return info The info.
    function getInfo() external view returns (Info memory info) {
        info.pool = address(pool);
        info.island = address(island);
        info.ranges = ranges;
        info.distX96 = distX96;
    }

    /* Callbacks */

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        address source = abi.decode(data, (address));
        TransferHelper.safeTransferFrom(
            token0,
            source,
            address(pool),
            amount0Owed
        );
        TransferHelper.safeTransferFrom(
            token1,
            source,
            address(pool),
            amount1Owed
        );
    }

    /* internal helpers */

    /// @notice Calculates the amount of shares for an island given the liquidity.
    /// @param liq The liquidity to convert to shares.
    /// @return shares The amount of shares.
    function islandLiqToShares(
        uint128 liq
    ) internal view returns (uint256 shares) {
        if (address(island) == address(0x0)) {
            revert NoIsland();
        }

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        (uint256 amount0, uint256 amount1) = getAmountsFromLiquidity(
            sqrtRatioX96,
            island.lowerTick(),
            island.upperTick(),
            liq
        );

        (, , shares) = island.getMintAmounts(amount0, amount1);
    }

    /// @notice Converts the amount of liquidity to amount0 and amount1.
    /// @param sqrtRatioX96 The price from slot0.
    /// @param tickLower The lower bound.
    /// @param tickUpper The upper bound.
    /// @param liquidity The liquidity to find amounts for.
    function getAmountsFromLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity,
            false
        );
    }

    function shift96(
        uint256 a,
        bool roundUp
    ) internal pure returns (uint256 b) {
        b = a >> 96;
        if (roundUp && (a & X96MASK) > 0) b += 1;
    }

    /// @notice Computes the name for the ERC20 token given the pool address.
    /// @param _pool The pool address.
    /// @return name The name of the ERC20 token.
    function nameFromPool(
        address _pool
    ) private view returns (string memory name) {
        address t0 = IUniswapV3Pool(_pool).token0();
        address t1 = IUniswapV3Pool(_pool).token1();
        name = string.concat(
            ERC20(t0).name(),
            "-",
            ERC20(t1).name(),
            "-Stable-KodiakLP"
        );
    }

    /// @notice Computes the symbol for the ERC20 token given the pool address.
    /// @param _pool The pool address.
    /// @return sym The symbol of the ERC20 token.
    function symbolFromPool(
        address _pool
    ) private view returns (string memory sym) {
        address t0 = IUniswapV3Pool(_pool).token0();
        address t1 = IUniswapV3Pool(_pool).token1();
        sym = string.concat(
            ERC20(t0).symbol(),
            "-",
            ERC20(t1).symbol(),
            "-SLP-KDK"
        );
    }
}
