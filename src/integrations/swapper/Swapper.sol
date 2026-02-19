// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";

/// @title Swapper
/// @notice A generalized batch swap helper. Tokens are sent to the contract first
/// (e.g. via collectEarnings), then swapAndForward consolidates them into a single
/// outToken via OogaBooga router calls and forwards the result to the caller.
contract Swapper is ReentrancyGuardTransient {
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
    /// @param txData Router calldata for each inToken swap. Empty = skip.
    /// @param minOutAmount Minimum outToken the caller must receive.
    /// @dev Intended for atomic use: send tokens to this contract and call swapAndForward
    /// in the same transaction (or rapid succession). Do not leave tokens sitting in this contract.
    function swapAndForward(
        address outToken,
        address[] calldata inTokens,
        bytes[] calldata txData,
        uint256 minOutAmount
    ) external nonReentrant returns (uint256 totalOut) {
        if (inTokens.length != txData.length) revert ArrayLengthMismatch();

        uint256 outBefore = IERC20(outToken).balanceOf(address(this));

        for (uint256 i = 0; i < inTokens.length; i++) {
            if (txData[i].length == 0) continue;
            uint256 balance = IERC20(inTokens[i]).balanceOf(address(this));
            if (balance == 0) continue;

            IERC20(inTokens[i]).forceApprove(router, balance);
            (bool success, ) = router.call(txData[i]);
            if (!success) revert RouterFailure();
            // Clear any residual approval to prevent leftover router allowances.
            IERC20(inTokens[i]).forceApprove(router, 0);
        }

        totalOut = IERC20(outToken).balanceOf(address(this)) - outBefore;
        if (totalOut < minOutAmount) revert MinOutAmountNotMet();
        TransferHelper.safeTransfer(outToken, msg.sender, totalOut);
    }
}
