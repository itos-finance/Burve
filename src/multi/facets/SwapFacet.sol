// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {RFTLib} from "Commons/Util/RFT.sol";
import {Store} from "../Store.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {AdjustorLib} from "../Adjustor.sol";
import {FullMath} from "../../FullMath.sol";
import {VertexId, VertexLib} from "../vertex/Id.sol";
import {ClosureId} from "../closure/Id.sol";
import {Closure} from "../closure/Closure.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {SafeCast} from "Commons/Math/Cast.sol";
import {IBurveMultiSwap} from "../interfaces/IBurveMultiSwap.sol";

/// Swap related functions
/// @dev Remember that amounts are real, but prices are nominal (meaning they should be around 1 to 1).
contract SwapFacet is IBurveMultiSwap, ReentrancyGuardTransient {
    /// We restrict swaps to be larger than this size as to avoid
    /// people gaming the deMinimus. Although even then, that's not too big of an issue.
    /// This is a nominal value.
    uint128 public constant MIN_SWAP_SIZE = 16e8;

    /// @inheritdoc IBurveMultiSwap
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
        require(!inVid.isEq(outVid), VacuousSwap()); // The user just ends up paying.
        // Validates the closure.
        ClosureId cid = ClosureId.wrap(_cid);
        Closure storage c = Store.closure(cid);
        uint256 realTax;
        {
            uint256 valueExchangedX128;
            uint256 nominalTax;

            if (amountSpecified > 0) {
                inAmount = uint256(amountSpecified);
                uint256 nominalIn = AdjustorLib.toNominal(
                    inVid.idx(),
                    inAmount,
                    false
                );
                require(
                    nominalIn >= MIN_SWAP_SIZE,
                    BelowMinSwap(nominalIn, MIN_SWAP_SIZE)
                );
                uint256 nominalOut;
                (nominalOut, nominalTax, valueExchangedX128) = c.swapInExact(
                    inVid,
                    outVid,
                    nominalIn
                );
                outAmount = AdjustorLib.toReal(outVid.idx(), nominalOut, false);
                // Figure out the tax in real terms. This is cheaper than another adjust call.
                // Round up to protect the vertex balance invariant.
                realTax = FullMath.mulDiv(inAmount, nominalTax, nominalIn);
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
                uint256 nominalIn;
                (nominalIn, nominalTax, valueExchangedX128) = c.swapOutExact(
                    inVid,
                    outVid,
                    nominalOut
                );
                require(
                    nominalIn >= MIN_SWAP_SIZE,
                    BelowMinSwap(nominalIn, MIN_SWAP_SIZE)
                );
                inAmount = AdjustorLib.toReal(inVid.idx(), nominalIn, true);
                realTax = FullMath.mulDiv(inAmount, nominalTax, nominalIn);
                if (amountLimit != 0) {
                    require(
                        inAmount <= amountLimit,
                        SlippageSurpassed(amountLimit, inAmount, false)
                    );
                }
            }
            emit SwapFeesEarned(inVid.idx(), outVid.idx(), nominalTax, realTax);
            emit Swap(
                msg.sender,
                recipient,
                inToken,
                outToken,
                inAmount,
                outAmount,
                valueExchangedX128
            );
        }

        if (inAmount > 0) {
            Store.vertex(outVid).withdraw(cid, outAmount, true);
            // Exchange balances
            if (msg.sender == recipient) {
                // We settle using RFTLib in this case.
                address[] memory tokens = new address[](2);
                tokens[0] = inToken;
                tokens[1] = outToken;
                int256[] memory amounts = new int256[](2);
                amounts[0] = SafeCast.toInt256(inAmount);
                amounts[1] = -SafeCast.toInt256(outAmount);
                RFTLib.settle(msg.sender, tokens, amounts, "");
            } else {
                TransferHelper.safeTransferFrom(
                    inToken,
                    msg.sender,
                    address(this),
                    inAmount
                );
                TransferHelper.safeTransfer(outToken, recipient, outAmount);
            }
            Store.vertex(inVid).deposit(cid, inAmount - realTax);
            // Finalize the closure with no value change.
            // Okay to do this after the settle, as we have a reentrancy guard.
            c.finalize(inVid, realTax, 0, 0);
            require(outAmount > 0, VacuousSwap());
        }
    }

    /// @inheritdoc IBurveMultiSwap
    function simSwap(
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint16 cid
    )
        external
        view
        returns (
            uint256 inAmount,
            uint256 outAmount,
            uint256 valueExchangedX128
        )
    {
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
            uint256 nominalOut;
            (nominalOut, , valueExchangedX128) = c.calcSwapInExact(
                inVid,
                outVid,
                nominalIn
            );
            outAmount = AdjustorLib.toReal(outVid.idx(), nominalOut, false);
        } else {
            outAmount = uint256(-amountSpecified);
            uint256 nominalOut = AdjustorLib.toNominal(
                outVid.idx(),
                outAmount,
                true
            );
            uint256 nominalIn;
            (nominalIn, , valueExchangedX128) = c.calcSwapOutExact(
                inVid,
                outVid,
                nominalOut
            );
            inAmount = AdjustorLib.toReal(inVid.idx(), nominalIn, true);
        }
    }
}
