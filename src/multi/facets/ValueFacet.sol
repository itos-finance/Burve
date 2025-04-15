// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SafeCast} from "Commons/Math/Cast.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {ClosureId} from "../closure/Id.sol";
import {Closure} from "../closure/Closure.sol";
import {TokenRegLib, TokenRegistry, MAX_TOKENS} from "../Token.sol";
import {VertexId, VertexLib} from "../vertex/Id.sol";
import {Vertex} from "../vertex/Vertex.sol";
import {Store} from "../Store.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {AssetBook} from "../Asset.sol";
import {AdjustorLib} from "../Adjustor.sol";
import {SearchParams} from "../Value.sol";

/*
 @notice The facet for minting and burning liquidity. We will have helper contracts
 that actually issue the ERC20 through these shares.

 @dev To conform to the ERC20 interface, we wrap each subset of tokens
 in their own ERC20 contract with mint functions that call the addLiq and removeLiq
functions here.

// TODO Do we need a view version of this facet?
*/
contract ValueFacet is ReentrancyGuardTransient {
    error DeMinimisDeposit();
    error InsufficientValueForBgt(uint256 value, uint256 bgtValue);
    error PastSlippageBounds();

    /// @notice Emitted when liquidity is added to a closure
    /// @param recipient The address that received the value
    /// @param closureId The ID of the closure
    /// @param amounts The amounts of each token added
    /// @param value The value added
    event AddValue(
        address indexed recipient,
        uint16 indexed closureId,
        uint128[] amounts,
        uint256 value
    );

    /// @notice Emitted when value is removed from a closure
    /// @param recipient The address that received the tokens
    /// @param closureId The ID of the closure
    /// @param amounts The amounts given
    /// @param value The value removed
    event RemoveValue(
        address indexed recipient,
        uint16 indexed closureId,
        uint256[] amounts,
        uint256 value
    );

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
        if (value == 0) revert DeMinimisDeposit();
        require(bgtValue <= value, InsufficientValueForBgt(value, bgtValue));
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid);
        uint256[MAX_TOKENS] memory requiredNominal = c.addValue(
            value,
            bgtValue
        );
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
        Store.assets().add(recipient, cid, value, bgtValue);
    }

    /// Add exactly this much value to the given closure by providing a single token.
    /// @param maxRequired Revert if required balance is greater than this.
    function addValueSingle(
        address recipient,
        uint16 _closureId,
        uint128 value,
        uint128 bgtValue,
        address token,
        uint128 maxRequired
    ) external nonReentrant returns (uint256 requiredBalance) {
        if (value == 0) revert DeMinimisDeposit();
        require(bgtValue <= value, InsufficientValueForBgt(value, bgtValue));
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid); // Validates cid.
        VertexId vid = VertexLib.newId(token); // Validates token.
        uint256 nominalRequired = c.addValueSingle(value, bgtValue, vid);
        requiredBalance = AdjustorLib.toReal(token, nominalRequired, true);
        require(requiredBalance <= maxRequired, PastSlippageBounds());
        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            requiredBalance
        );
        Store.vertex(vid).deposit(cid, requiredBalance);
        Store.assets().add(recipient, cid, value, bgtValue);
    }

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
        Store.vertex(vid).deposit(cid, amount);
        SearchParams memory search = Store.simplex().searchParams;
        uint256 bgtValue;
        (valueReceived, bgtValue) = c.addTokenForValue(
            vid,
            AdjustorLib.toNominal(token, amount, false), // Round down value deposited.
            bgtPercentX256,
            search
        );
        require(valueReceived > 0, DeMinimisDeposit());
        require(valueReceived >= minValue, PastSlippageBounds());
        Store.assets().add(recipient, cid, valueReceived, bgtValue);
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
        if (value == 0) revert DeMinimisDeposit();
        require(bgtValue <= value, InsufficientValueForBgt(value, bgtValue));
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid);
        uint256[MAX_TOKENS] memory nominalReceives = c.removeValue(
            value,
            bgtValue
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
        Store.assets().remove(msg.sender, cid, value, bgtValue);
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
        if (value == 0) revert DeMinimisDeposit();
        require(bgtValue <= value, InsufficientValueForBgt(value, bgtValue));
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid); // Validates cid.
        VertexId vid = VertexLib.newId(token); // Validates token.
        uint256 removedNominal = c.removeValueSingle(value, bgtValue, vid);
        removedBalance = AdjustorLib.toReal(token, removedNominal, false);
        require(removedBalance >= minReceive, PastSlippageBounds());
        // Users can removed locked tokens as it helps derisk this protocol.
        Store.vertex(vid).withdraw(cid, removedBalance, false);
        TransferHelper.safeTransfer(token, recipient, removedBalance);
        Store.assets().remove(msg.sender, cid, value, bgtValue);
    }

    /// Remove exactly this much of the given token for value in the given closure.
    /// @param maxValue Revert if valueGiven is larger than this.
    function removeSingleForValue(
        address recipient,
        uint16 _closureId,
        address token,
        uint128 amount,
        uint256 bgtPercentX256,
        uint128 maxValue
    ) external nonReentrant returns (uint256 valueGiven) {
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid); // Validates cid.
        VertexId vid = VertexLib.newId(token); // Validates token.
        SearchParams memory search = Store.simplex().searchParams;
        uint256 bgtValue;
        (valueGiven, bgtValue) = c.removeTokenForValue(
            vid,
            AdjustorLib.toNominal(token, amount, true), // Round up value removed.
            bgtPercentX256,
            search
        );
        require(valueGiven > 0, DeMinimisDeposit());
        require(valueGiven <= maxValue, PastSlippageBounds());
        Store.assets().remove(recipient, cid, valueGiven, bgtValue);
        // Users can removed locked tokens as it helps derisk this protocol.
        Store.vertex(vid).withdraw(cid, amount, false);
        TransferHelper.safeTransfer(token, recipient, amount);
    }

    /// Return the held value balance and earnings by an address in a given closure.
    function queryValue(
        address owner,
        uint16 closureId
    )
        external
        returns (
            uint256 value,
            uint256 bgtValue,
            uint256[MAX_TOKENS] memory earnings,
            uint256 bgtEarnings
        )
    {
        return Store.assets().query(owner, ClosureId.wrap(closureId));
    }
}
