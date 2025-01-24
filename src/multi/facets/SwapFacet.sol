// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/utils/ReentrancyGuardTransient.sol";
import {Edge} from "../Edge.sol";

contract SwapFacet is ReentrancyGuardTransient {
    function swap(
        address recipient,
        address inToken,
        address outToken,
        uint256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external nonReentrant {
        Edge storage edge = Store.edge(inToken, outToken);
        bool zeroForOne = inToken < outToken;
        edge.swap(
            recipient,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            data
        );
    }
}
