// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
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
    /// The wrapped pool
    IUniswapV3Pool public innerPool;
    address public token0;
    address public token1;

    /// The n ranges.
    TickRange[] public ranges;

    /// The relative liquidity for our n ranges.
    uint256[] public distX96;

    uint256 private constant X96MASK = (1 << 96) - 1;

    /// Thrown when the number of ranges and number of weights do not match.
    error MismatchedRangeWeightLengths(
        uint256 rangeLength,
        uint256 weightLength
    );

    /// If you burn too much liq at once, we can't collect that amount in one call.
    /// Please split up into multiple calls.
    error TooMuchBurnedAtOnce(uint128 liq, uint256 tokens, bool isX);

    function get_name(address pool) private view returns (string memory name) {
        address t0 = IUniswapV3Pool(pool).token0();
        address t1 = IUniswapV3Pool(pool).token1();
        name = string.concat(
            ERC20(t0).name(),
            "-",
            ERC20(t1).name(),
            "-Stable-KodiakLP"
        );
    }

    function get_symbol(address pool) private view returns (string memory sym) {
        address t0 = IUniswapV3Pool(pool).token0();
        address t1 = IUniswapV3Pool(pool).token1();
        sym = string.concat(
            ERC20(t0).symbol(),
            "-",
            ERC20(t1).symbol(),
            "-SLP-KDK"
        );
    }

    /// @param _pool The pool we are wrapping
    /// @param _ranges the n ranges
    /// @param _weights n weights defining the relative liquidity for each ranges
    constructor(
        address _pool,
        TickRange[] memory _ranges,
        uint128[] memory _weights
    ) ERC20(get_name(_pool), get_symbol(_pool)) {
        innerPool = IUniswapV3Pool(_pool);
        token0 = innerPool.token0();
        token1 = innerPool.token1();

        if (_ranges.length != _weights.length)
            revert MismatchedRangeWeightLengths(
                _ranges.length,
                _weights.length
            );

        for (uint256 i = 0; i < _ranges.length; ++i) {
            ranges.push(_ranges[i]);
        }

        uint256 sum = 0;
        for (uint256 i = 0; i < _weights.length; ++i) {
            sum += _weights[i];
        }

        for (uint256 i = 0; i < _weights.length; ++i) {
            distX96.push((_weights[i] << 96) / sum);
        }
    }

    function mint(address recipient, uint128 liq) external {
        for (uint256 i = 0; i < distX96.length; ++i) {
            TickRange memory range = ranges[i];
            uint128 amount = uint128(shift96(liq * distX96[i], true));

            innerPool.mint(
                address(this),
                range.lower,
                range.upper,
                amount,
                abi.encode(msg.sender)
            );
        }

        _mint(recipient, liq);
    }

    function burn(uint128 liq) external {
        _burn(msg.sender, liq);

        for (uint256 i = 0; i < distX96.length; ++i) {
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

    function shift96(
        uint256 a,
        bool roundUp
    ) internal pure returns (uint256 b) {
        b = a >> 96;
        if (roundUp && (a & X96MASK) > 0) b += 1;
    }
}
