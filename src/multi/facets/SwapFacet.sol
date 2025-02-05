// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Edge} from "../Edge.sol";
import {UniV3Edge} from "../UniV3Edge.sol";

contract SwapFacet is ReentrancyGuardTransient {
    function swap(
        address recipient,
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external nonReentrant returns (uint256 inAmount, uint256 outAmount) {
        address token0;
        address token1;
        bool zeroForOne;
        if (inToken < outToken) {
            (token0, token1) = (inToken, outToken);
            zeroForOne = true;
        } else {
            (token0, token1) = (outToken, inToken);
            zeroForOne = false;
        }

        Edge storage edge = Store.edge(token0, token1);
        (inAmount, outAmount) = edge.swap(
            token0,
            token1,
            recipient,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96
        );
    }

    function simSwap(
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )
        external
        view
        returns (int256 amount0, int256 amount1, uint160 finalSqrtPriceX96)
    {
        address token0;
        address token1;
        bool zeroForOne;
        if (inToken < outToken) {
            (token0, token1) = (inToken, outToken);
            zeroForOne = true;
        } else {
            (token0, token1) = (outToken, inToken);
            zeroForOne = false;
        }

        Edge storage edge = Store.edge(token0, token1);
        UniV3Edge.Slot0 memory slot0 = edge.getSlot0(
            token0,
            token1,
            !zeroForOne
        );
        (amount0, amount1, , finalSqrtPriceX96, ) = UniV3Edge.swap(
            edge,
            slot0,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96
        );
    }
}
