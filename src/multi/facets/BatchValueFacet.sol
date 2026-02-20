// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SafeCast} from "Commons/Math/Cast.sol";
import {RFTLib} from "Commons/Util/RFT.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {ClosureId} from "../closure/Id.sol";
import {Closure} from "../closure/Closure.sol";
import {VertexId, VertexLib} from "../vertex/Id.sol";
import {Store} from "../Store.sol";
import {AdjustorLib} from "../Adjustor.sol";
import {SearchParams} from "../Value.sol";
import {FullMath} from "../../FullMath.sol";
import {IBurveMultiEvents} from "../interfaces/IBurveMultiEvents.sol";
import {ValueErrors} from "./ValueFacet.sol";

/// @title BatchValueFacet
/// @notice Batch deposit of multiple tokens into a closure, emitting a single AddValue event.
///         This replaces the pattern of calling addSingleForValue() N times (once per token),
///         which emitted N separate AddValue events per logical deposit.
contract BatchValueFacet is ReentrancyGuardTransient {
    error LengthMismatch();
    error EmptyBatch();

    /// @notice Deposit multiple tokens into a closure in a single call.
    ///         Processes each token sequentially (order matters as each deposit changes closure state),
    ///         but emits only one aggregated AddValue event.
    /// @param recipient The address that receives the value position.
    /// @param _closureId The closure to deposit into.
    /// @param tokens Array of token addresses to deposit.
    /// @param amounts Array of token amounts to deposit (must match tokens length).
    /// @param bgtPercentX256 The percentage of value to designate as BGT value (X256 fixed-point).
    /// @param minTotalValue Revert if total value received is less than this.
    /// @return totalValueReceived The total value added to the closure.
    function addBatchSingleForValue(
        address recipient,
        uint16 _closureId,
        address[] calldata tokens,
        uint128[] calldata amounts,
        uint256 bgtPercentX256,
        uint128 minTotalValue
    ) external nonReentrant returns (uint256 totalValueReceived) {
        if (tokens.length != amounts.length) revert LengthMismatch();
        if (tokens.length == 0) revert EmptyBatch();

        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid);
        SearchParams memory search = Store.simplex().searchParams;

        uint256 totalBgtValue;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] == 0) continue;
            (uint256 valueReceived, uint256 bgtValue) = _depositToken(
                c, cid, _closureId, tokens[i], amounts[i], bgtPercentX256, search
            );
            totalValueReceived += valueReceived;
            totalBgtValue += bgtValue;
        }

        require(
            totalValueReceived >= minTotalValue,
            ValueErrors.PastSlippageBounds()
        );

        Store.assets().add(recipient, cid, totalValueReceived, totalBgtValue);

        // Single aggregated event for the entire batch deposit
        emit IBurveMultiEvents.AddValue(
            recipient,
            _closureId,
            totalValueReceived
        );
    }

    /// @dev Process a single token deposit within the batch. Separated to avoid stack-too-deep.
    function _depositToken(
        Closure storage c,
        ClosureId cid,
        uint16 _closureId,
        address token,
        uint128 amount,
        uint256 bgtPercentX256,
        SearchParams memory search
    ) private returns (uint256 valueReceived, uint256 bgtValue) {
        VertexId vid = VertexLib.newId(token);

        // Transfer token from sender via RFT
        {
            address[] memory t = new address[](1);
            int256[] memory d = new int256[](1);
            t[0] = token;
            d[0] = SafeCast.toInt256(amount);
            RFTLib.settle(msg.sender, t, d, "");
        }

        // Process deposit
        uint256 nominalIn = AdjustorLib.toNominal(token, amount, false);
        uint256 nominalTax;
        (valueReceived, nominalTax) = c.addTokenForValue(
            vid,
            nominalIn,
            search
        );
        require(valueReceived > 0, ValueErrors.DeMinimisDeposit());

        uint256 realTax = FullMath.mulDiv(amount, nominalTax, nominalIn);
        bgtValue = FullMath.mulX256(bgtPercentX256, valueReceived, true);

        emit IBurveMultiEvents.ClosureFeesEarned(
            _closureId,
            vid.idx(),
            nominalTax,
            realTax
        );
        c.finalize(
            vid,
            realTax,
            int256(uint256(valueReceived)),
            int256(uint256(bgtValue))
        );
        Store.vertex(vid).deposit(cid, amount - realTax);
    }
}
