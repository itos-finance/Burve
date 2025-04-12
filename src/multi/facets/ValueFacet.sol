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
    function addValue(
        address recipient,
        uint16 _closureId,
        uint256 value,
        uint256 bgtValue
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
                requiredBalances[i],
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
    function addValueSingle(
        address recipient,
        uint16 _closureId,
        uint256 value,
        uint256 bgtValue,
        address token
    ) external nonReentrant returns (uint256 requiredBalance) {
        if (value == 0) revert DeMinimisDeposit();
        require(bgtValue <= value, InsufficientValueForBgt(value, bgtValue));
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid); // Validates cid.
        VertexId vid = VertexLib.newId(token); // Validates token.
        uint256 nominalRequired = c.addValueSingle(value, bgtValue, vid);
        requiredBalance = AdjustorLib.toReal(token, nominalRequired, true);
        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            requiredBalance
        );
        Store.vertex(vid).deposit(cid, requiredBalance);
        Store.assets().add(recipient, cid, value, bgtValue);
    }

    /*
    /// Add exactly this much of the given token for value in the given closure.
    function addSingleForValue(
        address recipient,
        uint16 _closureId,
        address token,
        uint256 amount
    ) external nonReentrant returns (uint256 valueReceived) {
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid);
    }
    */

    /// Remove exactly this much value to the given closure and receive all tokens involved.
    function removeValue(
        address recipient,
        uint16 _closureId,
        uint256 value,
        uint256 bgtValue
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
                receivedBalances[i],
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
    function removeValueSingle(
        address recipient,
        uint16 _closureId,
        uint256 value,
        uint256 bgtValue,
        address token
    ) external nonReentrant returns (uint256 removedBalance) {
        if (value == 0) revert DeMinimisDeposit();
        require(bgtValue <= value, InsufficientValueForBgt(value, bgtValue));
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid); // Validates cid.
        VertexId vid = VertexLib.newId(token); // Validates token.
        uint256 removedNominal = c.removeValueSingle(value, bgtValue, vid);
        removedBalance = AdjustorLib.toReal(token, removedNominal, false);
        TransferHelper.safeTransfer(token, recipient, removedBalance);
        // Users can removed locked tokens as it helps derisk this protocol.
        Store.vertex(vid).withdraw(cid, removedBalance, false);
        Store.assets().remove(msg.sender, cid, value, bgtValue);
    }

    /*
    /// Remove exactly this much of the given token for value in the given closure.
    function removeSingleForValue(
        address recipient,
        uint16 _closureId,
        address token,
        uint256 amount
    ) external nonReentrant returns (uint256 valueGiven) {
        ClosureId cid = ClosureId.wrap(_closureId);
        Closure storage c = Store.closure(cid);
    }
    */

    /* helpers */
}
