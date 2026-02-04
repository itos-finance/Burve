// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {IBurveMultiSimplex} from "../../multi/interfaces/IBurveMultiSimplex.sol";
import {MAX_TOKENS} from "../../multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";

contract Closer is ReentrancyGuardTransient {
    address public immutable router;

    error InvalidPool();
    error InvalidToken();
    error SlippageExceeded();
    error RouterFailure();

    constructor(address _router) {
        router = _router;
    }

    /// Swap all tokens held by this contract (received from removeValue/collectEarnings)
    /// into a single output token and send to caller.
    /// @param pool The pool the tokens came from.
    /// @param outToken The desired output token.
    /// @param txData OogaBooga swap calldata per token index.
    /// @param minOutAmount Minimum final output token amount.
    /// @return outAmount The amount of outToken sent to the caller.
    function burn(
        address pool,
        address outToken,
        bytes[MAX_TOKENS] memory txData,
        uint256 minOutAmount
    ) external nonReentrant returns (uint256 outAmount) {
        address[] memory tokens = IBurveMultiSimplex(pool).getTokens();
        require(tokens.length <= MAX_TOKENS, InvalidPool());

        // Find outToken index.
        uint256 outIdx = MAX_TOKENS;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == outToken) {
                outIdx = i;
                break;
            }
        }
        if (outIdx >= MAX_TOKENS) {
            revert InvalidToken();
        }

        // Swap each non-outToken with a balance into outToken.
        for (uint256 i = 0; i < tokens.length; i++) {
            if (i == outIdx) continue;
            if (txData[i].length == 0) continue;

            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance == 0) continue;

            IERC20(tokens[i]).approve(router, balance);
            (bool success, ) = router.call(txData[i]);
            if (!success) revert RouterFailure();
        }

        // Transfer all outToken to caller.
        outAmount = IERC20(outToken).balanceOf(address(this));
        if (outAmount < minOutAmount) revert SlippageExceeded();
        TransferHelper.safeTransfer(outToken, msg.sender, outAmount);
    }
}
