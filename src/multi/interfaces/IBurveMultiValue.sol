// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MAX_TOKENS} from "../Constants.sol";

interface IBurveMultiValue {
    /// Add value by depositing pro-rata balances of each vertex in the closure.
    function addValue(
        address recipient,
        uint16 _closureId,
        uint128 value,
        uint128 bgtValue
    ) external returns (uint256[MAX_TOKENS] memory requiredBalances);

    /// Remove value by withdrawing pro-rata balances of each vertex in the closure.
    function removeValue(
        address recipient,
        uint16 _closureId,
        uint128 value,
        uint128 bgtValue
    ) external returns (uint256[MAX_TOKENS] memory receivedBalances);

    /// Add an exact amount of value to a given closure by depositing a single token.
    function addValueSingle(
        address recipient,
        uint16 _closureId,
        uint128 value,
        uint128 bgtValue,
        address token,
        uint128 maxRequired
    ) external returns (uint256 requiredBalance);

    /// Remove an exact amount of value from a given closure by withdrawing a single token.
    function removeValueSingle(
        address recipient,
        uint16 _closureId,
        uint128 value,
        uint128 bgtValue,
        address token,
        uint128 minReceive
    ) external returns (uint256 removedBalance);

    /// Add an exact amount of a single token to add value to a given closure.
    function addSingleForValue(
        address recipient,
        uint16 _closureId,
        address token,
        uint128 amount,
        uint256 bgtPercentX256,
        uint128 minValue
    ) external returns (uint256 valueReceived);

    /// Remove an exact amount of a single token to remove value from a given closure.
    function removeSingleForValue(
        address recipient,
        uint16 _closureId,
        address token,
        uint128 amount,
        uint256 bgtPercentX256,
        uint128 maxValue
    ) external returns (uint256 valueGiven);

    /// View the value and fee earnings for an owner's position in a given closure.
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
        );

    /// Collect fees earned by the msg.sender from a given closure and send to recipient.
    function collectEarnings(
        address recipient,
        uint16 closureId
    )
        external
        returns (
            uint256[MAX_TOKENS] memory collectedBalances,
            uint256 collectedBgt
        );
}
