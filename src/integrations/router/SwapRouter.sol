// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SwapFacet} from "../../../src/multi/facets/SwapFacet.sol";

/// @notice Defines the swap route per closure.
struct Route {
    /// The exact input when positive. The exact output when negative. Note that this is a real value.
    int240 amountSpecified;
    /// The closure we choose to swap through.
    uint16 cid;
}

/// Swap Router. For handling multiple swaps over multiple closures.
contract SwapRouter {
    error ExcessiveAmountIn(uint256 acceptable, uint256 actual);
    error InsufficientAmountOut(uint256 acceptable, uint256 actual);

    /// @notice Single hop token swap over multiple closures.
    /// @param recipient The recipient of the outToken.
    /// @param inToken Token to swap in.
    /// @param outToken Token to swap out.
    /// @param amountLimit When positive the maximum amount in. When negative the minimum amount out. Note that this is a real value.
    /// @param routes Closure routes to swap over.
    /// @dev There is no input validation that routes are all exact input or exact output.
    /// Or that the amount limit appropriately matches. Correctness is the responsability of the caller.
    /// Exact Input - route amountSpecified values are positive, amountLimit is positive to confirm minimum amount out.
    /// Exact Output - route amountSpecified values are negative, amountLimit is negative to confirm maximum amount in.
    function swap(
        address diamond,
        address recipient,
        address inToken,
        address outToken,
        int256 amountLimit,
        Route[] calldata routes
    ) external returns (uint256 inAmount, uint256 outAmount) {
        for (uint256 i = 0; i < routes.length; ++i) {
            Route memory route = routes[i];

            (uint256 _inAmount, uint256 _outAmount) = SwapFacet(diamond).swap(
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

        // Check amount in
        if (amountLimit > 0) {
            uint256 maxIn = uint256(amountLimit);
            require(inAmount <= maxIn, ExcessiveAmountIn(maxIn, inAmount));
        }

        // Check amount out
        if (amountLimit < 0) {
            uint256 minOut = uint256(-amountLimit);
            require(
                outAmount >= minOut,
                InsufficientAmountOut(minOut, outAmount)
            );
        }
    }
}
