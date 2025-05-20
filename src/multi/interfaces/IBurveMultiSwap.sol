// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBurveMultiSwap {
    /// We don't report prices because it's not useful since later swaps in other tokens
    /// can change other implied prices in the same hyper-edge.
    event Swap(
        address sender,
        address indexed recipient,
        address indexed inToken,
        address indexed outToken,
        uint256 inAmount,
        uint256 outAmount,
        uint256 valueExchangedX128
    ); // Real amounts.

    /// Fees earned from a a swap.
    /// @dev This specifies an edge to attribute the fees to.
    event SwapFeesEarned(
        uint8 indexed inIdx,
        uint8 indexed outIdx,
        uint256 nominalFees,
        uint256 realFees
    );

    /// Thrown when the amount in/out requested by the swap is larger/smaller than acceptable.
    error SlippageSurpassed(
        uint256 acceptableAmount,
        uint256 actualAmount,
        bool isOut
    );

    /// Non-empty input for an empty output. Undesirable for the swapper.
    error VacuousSwap();

    /// Attempted a swap smaller than the minimum.
    error BelowMinSwap(uint256 nominalSwapAttempted, uint256 minSwap);

    /// Swap one token for another.
    /// @param amountSpecified The exact input when positive, the exact output when negative.
    /// @param amountLimit When exact input, the minimum amount out. When exact output, the maximum amount in.
    /// However, if amountLimit is zero, it is not enforced. Note that this is a real value.
    /// @param _cid The closure we choose to swap through.
    function swap(
        address recipient,
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint256 amountLimit,
        uint16 _cid
    ) external returns (uint256 inAmount, uint256 outAmount);

    /// Simulate the swap of one token for another.
    /// @param amountSpecified The exact input when positive, the exact output when negative.
    /// @param cid The closure we choose to swap through.
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
        );
}
