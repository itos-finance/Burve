// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {IAdjustor} from "../../integrations/adjustor/IAdjustor.sol";
import {VertexId, VertexLib} from "../vertex/Id.sol";
import {SafeCast} from "Commons/Math/Cast.sol";

/// Swap related functions
/// @dev Remember that amounts are real, but prices are nominal (meaning they should be around 1 to 1).
contract SwapFacet is ReentrancyGuardTransient, BurveFacetBase {
    /// We don't report prices because it's not useful since later swaps in other tokens
    /// can change other implied prices in the same hyper-edge.
    event Swap(
        address sender,
        address indexed recipient,
        address indexed inToken,
        address indexed outToken,
        uint256 inAmount,
        uint256 outAmount
    ); // Real amounts.

    /// Thrown when the amount in/out requested by the swap is larger/smaller than acceptable.
    error SlippageSurpassed(
        uint256 acceptableAmount,
        uint256 actualAmount,
        bool isOut
    );

    /// Swap one token for another.
    /// @param amountSpecified The exact input when positive, the exact output when negative.
    /// @param amountLimit When exact input, the minimum amount out. When exact output, the maximum amount in.
    /// @param cid The closure we choose to swap through.
    function swap(
        address recipient,
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint256 amountLimit,
        uint16 _cid
    ) external nonReentrant returns (uint256 inAmount, uint256 outAmount) {
        // Validates the tokens.
        VertexId inVid = VertexLib.newId(inToken);
        VertexId outVid = VertexLib.newId(outToken);
        // Validates the closure.
        ClosureId cid = ClosureId.wrap(_cid);
        Closure storage c = Store.closure(cid);
        if (amountSpecified > 0) {
            inAmount = uint256(amountSpecified);
            uint256 nominalIn = AdjustorLib.toNominal(
                inVid.idx(),
                inAmount,
                false
            );
            uint256 nominalOut = c.swapInExact(inToken, outToken, nominalIn);
            outAmount = AdjustorLib.toReal(outVid.idx(), nominalOut, false);
            require(
                outAmount >= amountLimit,
                SlippageSurpassed(amountLimit, outAmount, true)
            );
        } else {
            outAmount = uint256(-amountSpecified);
            uint256 nominalOut = AdjustorLib.toNominal(
                outVid.idx(),
                outAmount,
                true
            );
            uint256 nominalIn = c.swapOutExact(inVid, outVid, nominalOut);
            inAmount = AdjustorLib.toReal(inVid.idx(), nominalIn, true);
            require(
                inAmount <= amountLimit,
                SlippageSurpassed(amountLimit, inAmount, false)
            );
        }
        if (inAmount > 0) {
            TransferHelper.safeTransferFrom(
                inToken,
                msg.sender,
                address(this),
                inAmount
            );
            Store.vertex(inVid).deposit(cid, inAmount);
            Store.vertex(outVid).withdraw(cid, outAmount, true);
            TransferHelper.safeTransfer(outToken, recipient, outAmount);
        }

        emit Swap(
            msg.sender,
            recipient,
            inToken,
            outToken,
            inAmount,
            outAmount
        );
    }

    /// Simulate the swap of one token for another.
    /// @param amountSpecified The exact input when positive, the exact output when negative.
    /// @param cid The closure we choose to swap through.
    function simSwap(
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint16 cid
    ) external view returns (uint256 inAmount, uint256 outAmount) {
        // Validates the tokens.
        VertexId inVid = VertexLib.newId(inToken);
        VertexId outVid = VertexLib.newId(outToken);
        Closure storage c = Store.closure(ClosureId.wrap(cid));
        if (amountSpecified > 0) {
            inAmount = uint256(amountSpecified);
            uint256 nominalIn = AdjustorLib.toNominal(
                inVid.idx(),
                inAmount,
                false
            );
            uint256 nominalOut = c.simSwapInExact(inToken, outToken, nominalIn);
            outAmount = AdjustorLib.toReal(outVid.idx(), nominalOut, false);
        } else {
            outAmount = uint256(-amountSpecified);
            uint256 nominalOut = AdjustorLib.toNominal(
                outVid.idx(),
                outAmount,
                true
            );
            uint256 nominalIn = c.swapOutExact(inVid, outVid, nominalOut);
            inAmount = AdjustorLib.toReal(inVid.idx(), nominalIn, true);
        }
    }
}
