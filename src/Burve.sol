// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV3Pool} from "./integrations/kodiak/IUniswapV3Pool.sol";
import {TransferHelper} from "./TransferHelper.sol";

/// Defines the tick range of an AMM position.
struct TickRange {
    /// Lower tick of the range.
    int24 lower;
    /// Upper tick of the range.
    int24 upper;
}

contract Burve is ERC20 {
    IKodiakIsland public island;

    IUniswapV3Pool public pool;
    address public token0;
    address public token1;

    /// The n ranges.
    TickRange[] public ranges;

    /// The relative liquidity for our n (pool) or 1 + n (island) ranges.
    /// If there is an island that distribution lies at index 0.
    uint256[] public distX96;

    uint256 private constant X96MASK = (1 << 96) - 1;

    /// Thrown when island specific logic is invoked but the contract was not initialized with an island.
    error NoIsland();

    /// Thrown when the number of ranges and number of weights do not match.
    error MismatchedRangeWeightLengths(
        uint256 rangeLength,
        uint256 weightLength
    );

    /// If you burn too much liq at once, we can't collect that amount in one call.
    /// Please split up into multiple calls.
    error TooMuchBurnedAtOnce(uint128 liq, uint256 tokens, bool isX);

    /// @param _island The island we are wrapping
    /// @param _ranges the n ranges
    /// @param _weights 1 + n weights defining the relative liquidity for each range. 
    ///         The first weight at index 0 is for the island.
    constructor(
        address _island,
        TickRange[] memory _ranges,
        uint128[] memory _weights
    ) ERC20(nameFromIsland(_island), symbolFromIsland(_island)) {
        island = IKodiakIsland(_island);
        pool = island.pool();

        if (_ranges.length + 1 != _weights.length) {
            revert MismatchedRangeWeightLengths(
                _ranges.length + 1,
                _weights.length
            );
        }

        _init(_ranges, _weights);
    }

    /// @param _pool The pool we are wrapping
    /// @param _ranges the n ranges
    /// @param _weights n weights defining the relative liquidity for each range.
    constructor(
        address _pool,
        TickRange[] memory _ranges,
        uint128[] memory _weights
    ) ERC20(nameFromPool(_pool), symbolFromPool(_pool)) {
        pool = IUniswapV3Pool(_pool);

        if (_ranges.length != _weights.length)
            revert MismatchedRangeWeightLengths(
                _ranges.length,
                _weights.length
            );

        _init(_ranges, _weights);
    }

    /// @notice initializes shared state between the two constructors.
    function _init(TickRange[] memory _ranges, uint128[] memory _weights) private {
        token0 = pool.token0();
        token1 = pool.token1();

        // copy ranges to storage
        for (uint256 i = 0; i < _ranges.length; ++i) {
            ranges.push(_ranges[i]);
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
        uint256 i = 0; 

        // mint the island
        if (island != address(0)) {
            uint128 liqAmount = uint128(shift96(liq * distX96[i], true));
            uint256 shares = islandLiqToShares(liqAmount);
            island.mint(shares, recipient);

            ++i;
        }

        // mint the V3 ranges
        while (i < distX96.length) {
            TickRange memory range = ranges[i];
            uint128 liqAmount = uint128(shift96(liq * distX96[i], true));

            innerPool.mint(
                address(this),
                range.lower,
                range.upper,
                liqAmount,
                abi.encode(msg.sender)
            );

            ++i;
        }

        _mint(recipient, liq);
    }

    /// @notice burns liquidity for the msg.sender
    function burn(uint128 liq) external {
        _burn(msg.sender, liq);

        uint256 i = 0;

        // burn the island
        if (island != address(0x0)) {
            uint128 liqAmount = uint128(shift96(liq * distX96[i], true));
            uint256 shares = islandLiqToShares(liqAmount);
            island.burnAmount(shares, msg.sender);

            ++i;
        }

        // burn the V3 ranges
        while (i < distX96.length) {
            TickRange memory range = ranges[i];
            uint128 amount = uint128(shift96(liq * distX96[i], false));

            (uint256 x, uint256 y) = innerPool.burn(
                range.lower,
                range.upper,
                amount
            );

            if (x > type(uint128).max) revert TooMuchBurnedAtOnce(liq, x, true);
            if (y > type(uint128).max)
                revert TooMuchBurnedAtOnce(liq, y, false);

            innerPool.collect(
                msg.sender,
                range.lower,
                range.upper,
                uint128(x),
                uint128(y)
            );

            ++i;
        }
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
            address(innerPool),
            amount0Owed
        );
        TransferHelper.safeTransferFrom(
            token1,
            source,
            address(innerPool),
            amount1Owed
        );
    }

    /* internal helpers */

    /// @notice Calculates the amount of shares in the island for the given liquidity.
    /// @notice Calculates the 
    function islandLiqToShares(uint128 liq) internal returns (uint256 shares) {
        if (address(island) == address(0x0)) {
            revert NoIsland();
        }

        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        (uint256 amount0, uint256 amount1) = getAmountsFromLiquidity(
            sqrtRatioX96,
            island.lowerTick(),
            island.upperTick(),
            islandLiq,
            false
        );

        (,, shares) = island.getMintAmounts(amount0, amount1);
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
        uint128 liquidity,
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
    /// @param pool The pool address.
    /// @return name The name of the ERC20 token.
    function nameFromPool(
        address pool
    ) private view returns (string memory name) {
        address t0 = IUniswapV3Pool(pool).token0();
        address t1 = IUniswapV3Pool(pool).token1();
        name = string.concat(
            ERC20(t0).name(),
            "-",
            ERC20(t1).name(),
            "-Stable-KodiakLP"
        );
    }

    /// @notice Computes the symbol for the ERC20 token given the pool address.
    /// @param pool The pool address.
    /// @return sym The symbol of the ERC20 token.
    function symbolFromPool(
        address pool
    ) private view returns (string memory sym) {
        address t0 = IUniswapV3Pool(pool).token0();
        address t1 = IUniswapV3Pool(pool).token1();
        sym = string.concat(
            ERC20(t0).symbol(),
            "-",
            ERC20(t1).symbol(),
            "-SLP-KDK"
        );
    }

    /// @notice Computes the name for the ERC20 token given the island address.
    /// @param island The island address.
    /// @return name The name of the ERC20 token.
    function nameFromIsland(
        address island
    ) private view returns (string memory name) {
        return nameFromPool(IKodiakIsland(island).pool());
    }

    /// @notice Computes the symbol for the ERC20 token given the island address.
    /// @param island The island address.
    /// @return sym The symbol of the ERC20 token.
    function symbolFromIsland(
        address island
    ) private view returns (string memory sym) {
        symbolFromPool(IKodiakIsland(island).pool());
    }
}
