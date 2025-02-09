// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/utils/ReentrancyGuardTransient.sol";
import {Edge} from "../Edge.sol";
import {BurveFacetBase} from "./Base.sol";

contract SwapFacet is ReentrancyGuardTransient, BurveFacetBase {
    function swap(
        address recipient,
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )
        external
        nonReentrant
        validTokens(inToken, outToken)
        returns (uint256 inAmount, uint256 outAmount)
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
        (inAmount, outAmount) = edge.swap(
            token0,
            token1,
            recipient,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96
        );
    }
}
