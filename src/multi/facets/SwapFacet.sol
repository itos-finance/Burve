// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {Edge, MIN_SQRT_PRICE_X96, MAX_SQRT_PRICE_X96} from "../Edge.sol";
import {UniV3Edge} from "../UniV3Edge.sol";
import {BurveFacetBase} from "./Base.sol";
import {newVertexId} from "../Vertex.sol";

contract SwapFacet is ReentrancyGuardTransient, BurveFacetBase {
    error SwapTokenLocked(address token);

    /// Swap one token for another.
    /// @param amountSpecified The exact input when positive, the exact output when negative.
    /// @param sqrtPriceLimitX96 is the NOMINAL square root price limit.
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
        // First check if any of the swap tokens are locked.
        if (Store.vertex(newVertexId(inToken)).isLocked())
            revert SwapTokenLocked(inToken);
        if (Store.vertex(newVertexId(outToken)).isLocked())
            revert SwapTokenLocked(outToken);
        // Note that we don't allow buying or selling a locked token.
        // In theory we could allow buys, but even if it repegs
        // the LVR capture is most likely worth more than the fees.
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

        exchange(
            recipient,
            inToken,
            inAmount,
            outToken,
            outAmount,
            protocolFee
        );

        emit Swap(
            msg.sender,
            recipient,
            inToken,
            outToken,
            inAmount,
            outAmount,
            finalSqrtPriceX96
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
        validTokens(inToken, outToken)
        returns (uint256 inAmount, uint256 outAmount, uint160 finalSqrtPriceX96)
    {
        (inAmount, outAmount, , finalSqrtPriceX96) = _preSwap(
            inToken,
            outToken,
            amountSpecified,
            sqrtPriceLimitX96
        );
    }

    /// Get the price of the pool denominated as the higher address token / the lower address token.
    /// @dev price convention is what it is to match uniswap's.
    /// @dev This is intended for front-end and other non-critical use cases where small variations
    /// price between teh time of query and time of use is not important. Thus the rounding is not specified.
    function getSqrtPrice(
        address inToken,
        address outToken
    )
        external
        view
        validTokens(inToken, outToken)
        returns (uint160 sqrtPriceX96)
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
        sqrtPriceX96 = slot0.sqrtPriceX96;
        console.log(slot0.sqrtPriceX96, "slotPrice");
        sqrtPriceX96 = uint160(
            FullMath.mulX128(
                slot0.sqrtPriceX96,
                Store.adjustor().realSqrtRatioX128(token1, token0, false),
                true
            ) // From our tests, rounding down then up will give the least residual errors.
        );
    }

    /* Helpers */

    function _preSwap(
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )
        private
        view
        returns (
            uint256 inAmount,
            uint256 outAmount,
            uint256 protocolFee,
            uint160 finalSqrtPriceX96
        )
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

        // Prep the swap.
        Edge storage edge = Store.edge(token0, token1);
        UniV3Edge.Slot0 memory slot0 = edge.getSlot0(
            token0,
            token1,
            !zeroForOne
        );

        // When we perform the swap calculation, we want to normalize the amounts, price, ticks, etc. around one.
        IAdjustor adj = Store.adjustor();
        // If positive, they want to spent at MOST that amount of the inToken, so we round the amount down.
        // If negative they want to get at LEAST that mount of the outToken, so we round the raw negative number down.
        amountSpecified = adj.toNominal(
            amountSpecified > 0 ? inToken : outToken,
            amountSpecified,
            false
        );
        // For the limit price we want to be conservative, so we round down on buys and up on sells.
        uint256 nomRatioX128 = adj.nominalSqrtRatioX128(
            token1,
            token0,
            zeroForOne
        );
        sqrtPriceLimitX96 = SafeCast.toUint160(
            FullMath.mulX128(sqrtPriceLimitX96, nomRatioX128, zeroForOne)
        );

        // Calculate the swap amounts and protocolFee
        int256 amount0;
        int256 amount1;
        (amount0, amount1, protocolFee, finalSqrtPriceX96, ) = UniV3Edge.swap(
            edge,
            slot0,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96
        );
        // Check the resulting final nominal price.
        if (
            (zeroForOne && (finalSqrtPriceX96 < MIN_SQRT_PRICE_X96)) ||
            (!zeroForOne && (finalSqrtPriceX96 > MAX_SQRT_PRICE_X96))
        ) revert SwapOutOfBounds(finalSqrtPriceX96);
        if (zeroForOne) {
            inAmount = uint256(amount0);
            outAmount = uint256(-amount1);
        } else {
            inAmount = uint256(amount1);
            outAmount = uint256(-amount0);
        }

        // Now we have to denormalize/convert the values to real amounts.
        if (amountSpecified > 0) {
            inAmount = uint256(amountSpecified);
            outAmount = adj.toReal(outToken, outAmount, false);
        } else {
            outAmount = uint256(-amountSpecified);
            inAmount = adj.toReal(inToken, inAmount, true);
        }
        protocolFee = adj.toReal(inToken, protocolFee, false);
        // The final price is purely cosmetic. It gets recalculated on the next swap anyways.
        // We know this fits because our real price is at most 20 whole bits, and
        // normalizing can at most add 18.
        finalSqrtPriceX96 = uint160(
            FullMath.mulDiv(finalSqrtPriceX96, 1 << 128, nomRatioX128)
        );
    }

    // Called to perform the actual exchange from one token balance to another.
    function exchange(
        address recipient,
        address inToken,
        uint256 inAmount,
        address outToken,
        uint256 outAmount,
        uint256 protocolFee
    ) private {
        VertexId inVid = newVertexId(inToken);
        VertexId outVid = newVertexId(outToken);
        // We send out the outtoken, and give the intoken to the appropriate closures.
        ClosureDist memory dist = Store.vertex(outVid).homSubtract(
            inVid,
            outAmount
        );
        if (outAmount > 0)
            TransferHelper.safeTransfer(outToken, recipient, outAmount);
        if (inAmount > 0)
            TransferHelper.safeTransferFrom(
                inToken,
                msg.sender,
                address(this),
                inAmount
            );
        // We leave the protocolFee on this contract.
        Store.vertex(inVid).homAdd(dist, inAmount - protocolFee);
    }
}
