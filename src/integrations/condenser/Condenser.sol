// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";

/// @title Condenser
/// @notice A generalized batch swap helper. Caller approves tokens, then swapAndForward
/// pulls them atomically, consolidates into a single outToken via OogaBooga router calls,
/// and forwards the result to the caller. No tokens should be left in this contract.
contract Condenser is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    address public immutable router;

    constructor(address _router) {
        router = _router;
    }

    error RouterFailure();
    error MinOutAmountNotMet();
    error ArrayLengthMismatch();

    /// Execute a batch of OogaBooga swaps, consolidating into outToken.
    /// @param outToken The single token to receive after all swaps.
    /// @param inTokens Array of tokens to swap (order matches txData).
    /// @param inAmounts Amount of each inToken to pull from the caller.
    /// @param txData Router calldata for each inToken swap. Empty = skip.
    /// @param minOutAmount Minimum outToken the caller must receive.
    function swapAndForward(
        address outToken,
        address[] calldata inTokens,
        uint256[] calldata inAmounts,
        bytes[] calldata txData,
        uint256 minOutAmount
    ) external nonReentrant returns (uint256 totalOut) {
        uint256 len = inTokens.length;
        if (len != txData.length || len != inAmounts.length) revert ArrayLengthMismatch();

        uint256 outBefore = IERC20(outToken).balanceOf(address(this));

        for (uint256 i = 0; i < len; i++) {
            if (txData[i].length == 0 || inAmounts[i] == 0) continue;

            // Pull tokens from caller — prevents theft of idle balances
            IERC20(inTokens[i]).safeTransferFrom(msg.sender, address(this), inAmounts[i]);

            IERC20(inTokens[i]).forceApprove(router, inAmounts[i]);
            (bool success,) = router.call(txData[i]);
            if (!success) revert RouterFailure();
            IERC20(inTokens[i]).forceApprove(router, 0);
        }

        totalOut = IERC20(outToken).balanceOf(address(this)) - outBefore;
        if (totalOut < minOutAmount) revert MinOutAmountNotMet();
        IERC20(outToken).safeTransfer(msg.sender, totalOut);
    }
}
