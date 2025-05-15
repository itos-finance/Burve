// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SwapFacet} from "../../../src/multi/facets/SwapFacet.sol";

/// @notice Defines the swap route per closure.
struct Route {
    /// The exact input when positive. The exact output when negative.
    int240 amountSpecified;
    /// The closure we choose to swap through.
    uint16 cid;
}

/// Swap Router. For handling multiple swaps over multiple closures.
contract SwapRouter {
    error ExceededMaximumAmountIn(
        uint256 acceptableAmountIn,
        uint256 actualAmountIn
    );
    error InsufficientMinimumAmountOut(
        uint256 acceptableAmountOut,
        uint256 actualAmountOut
    );

    SwapFacet swapFacet;

    constructor(address _swapFacet) {
        swapFacet = SwapFacet(_swapFacet);
    }

    /// @notice Single hop token swap over multiple closures.
    /// @param recipient The recipient of the outToken.
    /// @param inToken Token to swap in.
    /// @param outToken Token to swap out.
    /// @param amountLimit When positive the minimum amount out. When negative the maximum amount in.
    /// @param routes Closure routes to swap over.
    /// @dev There is no input validation that routes are all exact input or exact output.
    /// Or that the amount limit appropriately matches. Correctness is the responsability of the caller.
    /// Exact Input - route amountSpecified values are positive, amountLimit is positive to confirm minimum amount out.
    /// Exact Output - route amountSpecified values are negative, amountLimit is negative to confirm maximum amount in.
    function swap(
        address recipient,
        address inToken,
        address outToken,
        int256 amountLimit,
        Route[] memory routes
    ) external returns (uint256 inAmount, uint256 outAmount) {
        for (uint256 i = 0; i < routes.length; ++i) {
            Route memory route = routes[i];

            (uint256 _inAmount, uint256 _outAmount) = swapFacet.swap(
                recipient,
                inToken,
                outToken,
                route.amountSpecified,
                0,
                route.cid
            );
            inAmount += _inAmount;
            outAmount += _outAmount;
        }

        // Check amount out
        if (amountLimit > 0) {
            require(
                outAmount >= uint256(amountLimit),
                InsufficientMinimumAmountOut(uint256(amountLimit), outAmount)
            );
        }

        // Check amount in
        if (amountLimit < 0) {
            uint256 convertedAmountLimit = uint256(int256(-amountLimit));
            require(
                inAmount <= convertedAmountLimit,
                ExceededMaximumAmountIn(convertedAmountLimit, inAmount)
            );
        }
    }
}
