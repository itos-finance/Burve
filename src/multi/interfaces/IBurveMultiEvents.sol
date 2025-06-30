// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MAX_TOKENS} from "../Constants.sol";

interface IBurveMultiEvents {
    /// Emitted when overall simplex fees are changed..
    event SimplexFeesSet(uint128 defaultEdgeFeeX128, uint128 protocolTakeX128);
    /// Emitted when the edge fee is set.
    event EdgeFeeSet(uint8 indexed i, uint8 indexed j, uint128 edgeFeeX128);
    // Emitted whenever the balances change.
    event NewClosureBalances(
        uint16 cid,
        uint256 targetX128,
        uint256[MAX_TOKENS] balances
    );

    /// @notice Emitted when a closure earns frees from a single value deposit.
    event ClosureFeesEarned(
        uint16 indexed closureId,
        uint8 indexed vertexIdx,
        uint256 nominalFees,
        uint256 realFees
    );

    /// @notice Emitted when liquidity is added to a closure
    /// @param recipient The address that received the value
    /// @param closureId The ID of the closure
    /// @param value The value added
    event AddValue(
        address indexed recipient,
        uint16 indexed closureId,
        uint256 value
    );

    /// @notice Emitted when value is removed from a closure
    /// @param recipient The address that received the tokens
    /// @param closureId The ID of the closure
    /// @param value The value removed
    event RemoveValue(
        address indexed recipient,
        uint16 indexed closureId,
        uint256 value
    );

    /// @notice Emitted when fees are removed from a position
    /// @param recipient The address that received the tokens
    /// @param closureId The ID of the closure
    /// @param deltas The amounts of each token removed as fees from the position
    event CollectFees(
        address indexed recipient,
        uint16 indexed closureId,
        int256[] deltas
    );
}
