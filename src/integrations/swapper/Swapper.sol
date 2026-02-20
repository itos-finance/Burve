// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";

/// @title Swapper
/// @notice Pull-based batch swap helper. Caller approves this contract, then
///         swapAndForward pulls tokens via transferFrom, swaps them through
///         the OogaBooga router, and forwards the consolidated outToken to the caller.
///         No tokens should ever idle in this contract.
contract Swapper is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    address public immutable router;

    constructor(address _router) {
        router = _router;
    }

    error RouterFailure();
    error MinOutAmountNotMet();
    error ArrayLengthMismatch();

    /// @notice Execute a batch of OogaBooga swaps, consolidating into outToken.
    /// @param outToken The single token to receive after all swaps.
    /// @param inTokens Array of tokens to swap (order matches amounts and txData).
    /// @param amounts Amount of each inToken to pull from the caller via transferFrom.
    /// @param txData Router calldata for each inToken swap. Empty = skip (token forwarded as-is if it equals outToken).
    /// @param minOutAmount Minimum outToken the caller must receive.
    /// @return totalOut The amount of outToken sent to the caller.
    function swapAndForward(
        address outToken,
        address[] calldata inTokens,
        uint256[] calldata amounts,
        bytes[] calldata txData,
        uint256 minOutAmount
    ) external nonReentrant returns (uint256 totalOut) {
        if (inTokens.length != txData.length || inTokens.length != amounts.length)
            revert ArrayLengthMismatch();

        // Snapshot outToken balance before any pulls or swaps.
        uint256 outBefore = IERC20(outToken).balanceOf(address(this));

        // Pull tokens from caller.
        for (uint256 i = 0; i < inTokens.length; i++) {
            if (amounts[i] == 0) continue;
            IERC20(inTokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);
        }

        // Execute swaps via router.
        for (uint256 i = 0; i < inTokens.length; i++) {
            if (txData[i].length == 0) continue;
            uint256 balance = IERC20(inTokens[i]).balanceOf(address(this));
            if (balance == 0) continue;

            IERC20(inTokens[i]).forceApprove(router, balance);
            (bool success, ) = router.call(txData[i]);
            if (!success) revert RouterFailure();
            // Clear residual approval.
            IERC20(inTokens[i]).forceApprove(router, 0);
        }

        totalOut = IERC20(outToken).balanceOf(address(this)) - outBefore;
        if (totalOut < minOutAmount) revert MinOutAmountNotMet();
        IERC20(outToken).safeTransfer(msg.sender, totalOut);

        // Sweep any residual inToken balances back to caller (partial fills, dust).
        for (uint256 i = 0; i < inTokens.length; i++) {
            if (inTokens[i] == outToken) continue;
            uint256 residual = IERC20(inTokens[i]).balanceOf(address(this));
            if (residual > 0) {
                IERC20(inTokens[i]).safeTransfer(msg.sender, residual);
            }
        }
    }
}
