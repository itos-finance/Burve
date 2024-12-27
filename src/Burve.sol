// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV3Pool} from "./integrations/kodiak/IUniswapV3Pool.sol";
import {TransferHelper} from "./TransferHelper.sol";

contract Burve is ERC20 {
    /// The wrapped pool
    IUniswapV3Pool public innerPool;
    address public token0;
    address public token1;
    /// The n+1 tick boundaries for our n ranges.
    int24[] public breaks;
    /// The relative liquidity for our n ranges.
    uint256[] public distX96;

    uint256 private constant X96MASK = (1 << 96) - 1;

    /// Thrown when the number of ranges implied by breaks is different from the number implied by dists.
    error MismatchedRangeLengths(uint256 breakLength, uint256 distLength);
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

    /// @param _pool The pool we're wrapping and depositing into
    /// @param _breaks n+1 sorted tick entries definiting the n ranges
    /// @param _dist n weights defining the relative liquidity deposits in the n rnages
    constructor(
        address _pool,
        int24[] memory _breaks,
        uint128[] memory _dist
    ) ERC20(get_name(_pool), get_symbol(_pool)) {
        innerPool = IUniswapV3Pool(_pool);
        token0 = innerPool.token0();
        token1 = innerPool.token1();
        if (_breaks.length != _dist.length + 1)
            revert MismatchedRangeLengths(_breaks.length - 1, _dist.length);

        for (uint256 i = 0; i < _breaks.length; ++i) {
            breaks.push(_breaks[i]);
        }
        uint256 sum = 0;
        for (uint256 j = 0; j < _dist.length; ++j) {
            sum += _dist[j];
        }
        for (uint256 k = 0; k < _dist.length; ++k) {
            distX96.push((_dist[k] << 96) / sum);
        }
    }

    function mint(address recipient, uint128 liq) external {
        for (uint256 i = 0; i < distX96.length; ++i) {
            uint128 amount = uint128(shift96(liq * distX96[i], true));
            innerPool.mint(
                address(this),
                breaks[i],
                breaks[i + 1],
                amount,
                abi.encode(msg.sender)
            );
        }
        _mint(recipient, liq);
    }

    function burn(uint128 liq) external {
        _burn(msg.sender, liq);
        for (uint256 i = 0; i < distX96.length; ++i) {
            uint128 amount = uint128(shift96(liq * distX96[i], false));
            (uint256 x, uint256 y) = innerPool.burn(
                breaks[i],
                breaks[i + 1],
                amount
            );
            if (x > type(uint128).max) revert TooMuchBurnedAtOnce(liq, x, true);
            if (y > type(uint128).max)
                revert TooMuchBurnedAtOnce(liq, y, false);
            innerPool.collect(
                msg.sender,
                breaks[i],
                breaks[i + 1],
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
