// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SafeCast} from "Commons/Math/Cast.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {ClosureId} from "../closure/Id.sol";
import {Closure} from "../closure/Closure.sol";
import {TokenRegistry, MAX_TOKENS} from "../Token.sol";
import {VertexId, VertexLib} from "../vertex/Id.sol";
import {Store} from "../Store.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {AdjustorLib} from "../Adjustor.sol";
import {SearchParams} from "../Value.sol";
import {IBGTExchanger} from "../../integrations/BGTExchange/IBGTExchanger.sol";
import {ReserveLib} from "../vertex/Reserve.sol";
import {FullMath} from "../../FullMath.sol";
import {IBurveMultiEvents} from "../interfaces/IBurveMultiEvents.sol";

interface ValueErrors {
    error DeMinimisDeposit();
    error InsufficientValueForBgt(uint256 value, uint256 bgtValue);
    error PastSlippageBounds();
}

/*
 Value functions are so large we split the operations across 5 facets.
 But you should access them through the single IBurveMultiValue interface.
*/

/// Generic operations relating to value stored in the pool.
contract ValueFacet is ReentrancyGuardTransient {
    /// Add exactly this much value to the given closure by providing all tokens involved.
    /// @dev Use approvals to limit slippage, or you can wrap this with a helper contract
    /// which validates the requiredBalances are small enough according to some logic.
    function addValue(
        address recipient,
        uint16 _closureId,
        uint128 value,
        uint128 bgtValue
    )
        external
        nonReentrant
        returns (uint256[MAX_TOKENS] memory requiredBalances)
    {
        if (value == 0) revert ValueErrors.DeMinimisDeposit();
        require(
            bgtValue <= value,
            ValueErrors.InsufficientValueForBgt(value, bgtValue)
        );
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid);
        uint256[MAX_TOKENS] memory requiredNominal = c.addValue(value);
        // Fetch balances
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            if (!cid.contains(i)) continue; // Irrelevant token.
            address token = tokenReg.tokens[i];
            uint256 realNeeded = AdjustorLib.toReal(
                token,
                requiredNominal[i],
                true
            );
            requiredBalances[i] = realNeeded;
            TransferHelper.safeTransferFrom(
                token,
                msg.sender,
                address(this),
                realNeeded
            );
            Store.vertex(VertexLib.newId(i)).deposit(cid, realNeeded);
        }
        c.finalize(
            VertexId.wrap(0),
            0,
            int256(uint256(value)),
            int256(uint256(bgtValue))
        );
        Store.assets().add(recipient, cid, value, bgtValue);
        emit IBurveMultiEvents.AddValue(recipient, _closureId, value);
    }

    /// Remove exactly this much value to the given closure and receive all tokens involved.
    /// @dev Wrap this with a helper contract which validates the received balances are sufficient.
    function removeValue(
        address recipient,
        uint16 _closureId,
        uint128 value,
        uint128 bgtValue
    )
        external
        nonReentrant
        returns (uint256[MAX_TOKENS] memory receivedBalances)
    {
        if (value == 0) revert ValueErrors.DeMinimisDeposit();
        require(
            bgtValue <= value,
            ValueErrors.InsufficientValueForBgt(value, bgtValue)
        );
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid);
        uint256[MAX_TOKENS] memory nominalReceives = c.removeValue(value);
        Store.assets().remove(msg.sender, cid, value, bgtValue);
        c.finalize(
            VertexId.wrap(0),
            0,
            -int256(uint256(value)),
            -int256(uint256(bgtValue))
        );

        // Send balances
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            if (!cid.contains(i)) continue;
            address token = tokenReg.tokens[i];
            uint256 realSend = AdjustorLib.toReal(
                token,
                nominalReceives[i],
                false
            );
            receivedBalances[i] = realSend;
            // Users can remove value even if the token is locked. It actually helps derisk us.
            Store.vertex(VertexLib.newId(i)).withdraw(cid, realSend, false);
            TransferHelper.safeTransfer(token, recipient, realSend);
        }
        emit IBurveMultiEvents.RemoveValue(recipient, _closureId, value);
    }

    function collectEarnings(
        address recipient,
        uint16 closureId
    )
        external
        returns (
            uint256[MAX_TOKENS] memory collectedBalances,
            uint256 collectedBgt
        )
    {
        ClosureId cid = ClosureId.wrap(closureId);
        // Catch up on rehypothecation gains before we claim fees.
        Store.closure(cid).trimAllBalances();
        uint256[MAX_TOKENS] memory collectedShares;
        (collectedShares, collectedBgt) = Store.assets().claimFees(
            msg.sender,
            cid
        );
        if (collectedBgt > 0)
            IBGTExchanger(Store.simplex().bgtEx).withdraw(
                recipient,
                collectedBgt
            );
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            if (collectedShares[i] > 0) {
                VertexId vid = VertexLib.newId(i);
                // Real amounts.
                collectedBalances[i] = ReserveLib.withdraw(
                    vid,
                    collectedShares[i]
                );
                TransferHelper.safeTransfer(
                    tokenReg.tokens[i],
                    recipient,
                    collectedBalances[i]
                );
            }
        }
    }
}

contract ValueSingleFacet is ReentrancyGuardTransient {
    /// Add exactly this much value to the given closure by providing a single token.
    /// @param maxRequired Revert if required balance is greater than this. (0 indicates no restriction).
    function addValueSingle(
        address recipient,
        uint16 _closureId,
        uint128 value,
        uint128 bgtValue,
        address token,
        uint128 maxRequired
    ) external nonReentrant returns (uint256 requiredBalance) {
        if (value == 0) revert ValueErrors.DeMinimisDeposit();
        require(
            bgtValue <= value,
            ValueErrors.InsufficientValueForBgt(value, bgtValue)
        );
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid); // Validates cid.
        VertexId vid = VertexLib.newId(token); // Validates token.
        (uint256 nominalRequired, uint256 nominalTax) = c.addValueSingle(
            value,
            vid
        );
        requiredBalance = AdjustorLib.toReal(token, nominalRequired, true);
        uint256 realTax = FullMath.mulDiv(
            requiredBalance,
            nominalTax,
            nominalRequired
        );
        if (maxRequired > 0)
            require(
                requiredBalance <= maxRequired,
                ValueErrors.PastSlippageBounds()
            );
        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            requiredBalance
        );
        emit IBurveMultiEvents.ClosureFeesEarned(
            _closureId,
            vid.idx(),
            nominalTax,
            realTax
        );
        c.finalize(
            vid,
            realTax,
            int256(uint256(value)),
            int256(uint256(bgtValue))
        );
        Store.vertex(vid).deposit(cid, requiredBalance - realTax);
        Store.assets().add(recipient, cid, value, bgtValue);
        emit IBurveMultiEvents.AddValue(recipient, _closureId, value);
    }

    /// Remove exactly this much value to the given closure by receiving a single token.
    /// @param minReceive Revert if removedBalance is smaller than this.
    function removeValueSingle(
        address recipient,
        uint16 _closureId,
        uint128 value,
        uint128 bgtValue,
        address token,
        uint128 minReceive
    ) external nonReentrant returns (uint256 removedBalance) {
        if (value == 0) revert ValueErrors.DeMinimisDeposit();
        require(
            bgtValue <= value,
            ValueErrors.InsufficientValueForBgt(value, bgtValue)
        );
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid); // Validates cid.
        VertexId vid = VertexLib.newId(token); // Validates token.
        (uint256 removedNominal, uint256 nominalTax) = c.removeValueSingle(
            value,
            vid
        );
        Store.assets().remove(msg.sender, cid, value, bgtValue);
        uint256 realRemoved = AdjustorLib.toReal(token, removedNominal, false);
        Store.vertex(vid).withdraw(cid, realRemoved, false);
        uint256 realTax = FullMath.mulDiv(
            realRemoved,
            nominalTax,
            removedNominal
        );
        emit IBurveMultiEvents.ClosureFeesEarned(
            _closureId,
            vid.idx(),
            nominalTax,
            realTax
        );
        c.finalize(
            vid,
            realTax,
            -int256(uint256(value)),
            -int256(uint256(bgtValue))
        );
        removedBalance = realRemoved - realTax; // How much the user actually gets.
        require(removedBalance >= minReceive, ValueErrors.PastSlippageBounds());
        TransferHelper.safeTransfer(token, recipient, removedBalance);
        emit IBurveMultiEvents.RemoveValue(recipient, _closureId, value);
    }
}

/// Adding and removing liquidity by specifying an exact token balance.
contract AddTokenValueFacet is ReentrancyGuardTransient {
    /// Add exactly this much of the given token for value in the given closure.
    /// @param minValue Revert if valueReceived is smaller than this.
    function addSingleForValue(
        address recipient,
        uint16 _closureId,
        address token,
        uint128 amount,
        uint256 bgtPercentX256,
        uint128 minValue
    ) external nonReentrant returns (uint256 valueReceived) {
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid); // Validates cid.
        VertexId vid = VertexLib.newId(token); // Validates token.
        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );
        SearchParams memory search = Store.simplex().searchParams;
        uint256 nominalTax;
        uint256 nominalIn = AdjustorLib.toNominal(token, amount, false); // Round down value deposited.
        (valueReceived, nominalTax) = c.addTokenForValue(
            vid,
            nominalIn,
            search
        );
        require(valueReceived > 0, ValueErrors.DeMinimisDeposit());
        require(valueReceived >= minValue, ValueErrors.PastSlippageBounds());
        uint256 realTax = FullMath.mulDiv(amount, nominalTax, nominalIn);
        uint256 bgtValue = FullMath.mulX256(
            bgtPercentX256,
            valueReceived,
            true
        );
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
        Store.assets().add(recipient, cid, valueReceived, bgtValue);
        emit IBurveMultiEvents.AddValue(recipient, _closureId, valueReceived);
    }
}

contract RemoveTokenValueFacet is ReentrancyGuardTransient {
    /// Remove exactly this much of the given token for value in the given closure.
    /// @param maxValue Revert if valueGiven is larger than this. (Not enforced if zero.)
    function removeSingleForValue(
        address recipient,
        uint16 _closureId,
        address token,
        uint128 amount,
        uint256 bgtPercentX256,
        uint128 maxValue
    ) external nonReentrant returns (uint256 valueGiven) {
        VertexId vid = VertexLib.newId(token); // Validates token.
        uint256 nominalReceive = AdjustorLib.toNominal(token, amount, true); // RoundUp value removed.
        valueGiven = _removeSingleForValue(
            _closureId,
            vid,
            amount,
            nominalReceive,
            bgtPercentX256
        );
        require(valueGiven > 0, ValueErrors.DeMinimisDeposit());
        if (maxValue > 0)
            require(valueGiven <= maxValue, ValueErrors.PastSlippageBounds());
        // Round up because we must suffice for amount and the realTax.
        TransferHelper.safeTransfer(token, recipient, amount);
        emit IBurveMultiEvents.RemoveValue(recipient, _closureId, valueGiven);
    }

    /// Internal function for dealing with the large number of stack variables.
    function _removeSingleForValue(
        uint16 _closureId,
        VertexId vid,
        uint128 amount,
        uint256 nominalAmount,
        uint256 bgtPercentX256
    ) private returns (uint256 valueGiven) {
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid); // Validates cid.
        uint256 realTax;
        {
            uint256 nominalTax;
            (valueGiven, nominalTax) = c.removeTokenForValue(
                vid,
                nominalAmount,
                Store.simplex().searchParams
            );
            // Round down to avoid removing too much from the vertex.
            realTax = FullMath.mulDiv(amount, nominalTax, nominalAmount);
            emit IBurveMultiEvents.ClosureFeesEarned(
                _closureId,
                vid.idx(),
                nominalTax,
                realTax
            );
        }
        Store.vertex(vid).withdraw(cid, amount + realTax, true);
        {
            // Round up to handle the 0% and 100% cases exactly.
            uint256 bgtValue = FullMath.mulX256(
                bgtPercentX256,
                valueGiven,
                true
            );
            Store.assets().remove(msg.sender, cid, valueGiven, bgtValue);
            c.finalize(
                vid,
                realTax,
                -int256(uint256(valueGiven)),
                -int256(uint256(bgtValue))
            );
        }
    }
}

contract QueryValueFacet {
    /// Return the held value balance and earnings by an address in a given closure.
    function queryValue(
        address owner,
        uint16 closureId
    )
        external
        view
        returns (
            uint256 value,
            uint256 bgtValue,
            uint256[MAX_TOKENS] memory earnings,
            uint256 bgtEarnings
        )
    {
        ClosureId cid = ClosureId.wrap(closureId);
        (
            uint256[MAX_TOKENS] memory realEPVX128,
            uint256 bpvX128,
            uint256[MAX_TOKENS] memory upvX128
        ) = Store.closure(cid).viewTrimAll();
        (value, bgtValue, earnings, bgtEarnings) = Store.assets().query(
            owner,
            cid
        );
        uint256 nonValue = value - bgtValue;
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            if (earnings[i] > 0) {
                VertexId vid = VertexLib.newId(i);
                earnings[i] = ReserveLib.query(vid, earnings[i]);
                earnings[i] += FullMath.mulX128(
                    realEPVX128[i],
                    nonValue,
                    false
                );
                earnings[i] += FullMath.mulX128(upvX128[i], bgtValue, false);
            }
        }
        bgtEarnings += FullMath.mulX128(bpvX128, bgtValue, false);
    }
}
