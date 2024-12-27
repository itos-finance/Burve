// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "openzeppelin-contracts/ERC20.sol";
import {IUniswapV3Pool} from "./integrations/kodiak/IUniswapV3Pool.sol";

contract Burve is ERC20 {
    /// The wrapped pool
    address public innerPool;
    address public token0;
    address public token1;
    /// The n+1 tick boundaries for our n ranges.
    int24[] public breaks;
    /// The relative liquidity for our n ranges.
    uint256[] public distX96;

    uint256 private constant X96MASK = (1 << 96) - 1;

    error MismatchedRangeLengths(uint256 breakLength, uint256 distLength);

    /// @param _pool The pool we're wrapping and depositing into
    /// @param _breaks n+1 sorted tick entries definiting the n ranges
    /// @param _dist n weights defining the relative liquidity deposits in the n rnages
    constructor(
        IUniswapV3Pool _pool,
        int24[] calldata _breaks,
        uint128[] calldata _dist
    ) {
        innerPool = IUniswapV3Pool(pool);
        if (_breaks.length != _dist.length + 1)
            revert MismatchedRangeLengths(_breaks.length - 1, dist.length);

        for (uint256 i = 0; i < _breaks.length; ++i) {
            breaks.push(_breaks[i]);
        }
        uint256 sum = 0;
        for (uint256 j = 0; j < _dist.length; ++j) {
            sum += dist[j];
        }
        for (uint256 k = 0; k < _dist.length; ++k) {
            distX96.push((dist[k] << 96) / sum);
        }
    }

    function mint(address recipient, uint128 liq) external {
        for (uint256 i = 0; i < distX96.length; ++i) {
            uint128 amount = shift96(liq * distX96[i], true);
            innerpool.mint(
                recipient,
                breaks[i],
                breaks[i + 1],
                amount,
                abi.encode(msg.sender)
            );
        }
    }

    function burn(uint128 liq) external {
        for (uint256 i = 0; i < distX96.length; ++i) {
            uint128 amount = shift96(liq * distX96[i], false);
            innerpool.burn(breaks[i], breaks[i + 1], amount);
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

    function shift96(uint256 a, bool roundUp) internal returns (uint256 b) {
        b = a >> 96;
        if (roundUp && (a & X96MASK) > 0) b += 1;
    }
}
