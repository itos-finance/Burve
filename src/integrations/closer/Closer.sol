// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {IBurveMultiValue} from "../../multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../multi/interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "../../multi/facets/ValueTokenFacet.sol";
import {MAX_TOKENS} from "../../multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";

contract Closer is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    address public immutable router;

    constructor(address _router) {
        router = _router;
    }

    error InvalidToken();
    error RouterFailure();
    error MinOutAmountNotMet();

    /// Remove value from a closure, swap all received tokens into a single outToken, and send to the user.
    /// @param pool The pool to remove value from.
    /// @param outToken The token to receive after swapping.
    /// @param closureId The closure to remove value from.
    /// @param value The value to remove.
    /// @param bgtValue The BGT value to remove.
    /// @param txData The calldata to execute on the router for swapping each non-outToken.
    /// @param minAmountsReceived Per-token minimums passed to removeValue as amountLimits.
    /// @param minOutAmount Minimum total outToken the user must receive.
    /// @return totalOut The total outToken sent to the user.
    function burn(
        address pool,
        address outToken,
        uint16 closureId,
        uint128 value,
        uint128 bgtValue,
        bytes[MAX_TOKENS] memory txData,
        uint256[MAX_TOKENS] calldata minAmountsReceived,
        uint256 minOutAmount
    ) external nonReentrant returns (uint256 totalOut) {
        // 1. Validate outToken against pool token list.
        address[] memory tokens = IBurveMultiSimplex(pool).getTokens();
        uint256 outTokenIdx = MAX_TOKENS;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == outToken) {
                outTokenIdx = i;
                break;
            }
        }
        if (outTokenIdx >= MAX_TOKENS) {
            revert InvalidToken();
        }

        // 2. Snapshot all token balances to scope approvals to only what removeValue provides.
        uint256[MAX_TOKENS] memory balancesBefore;
        for (uint256 i = 0; i < tokens.length; i++) {
            balancesBefore[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        // 3. Transfer value position from user to this contract.
        ValueTokenFacet(pool).transferFrom(
            msg.sender,
            address(this),
            closureId,
            value,
            bgtValue
        );

        // 4. Remove value — tokens arrive at this contract.
        IBurveMultiValue(pool).removeValue(
            address(this),
            closureId,
            value,
            bgtValue,
            minAmountsReceived
        );

        // 5. Swap only the received amounts (not pre-existing balances) into outToken via router.
        for (uint256 i = 0; i < tokens.length; i++) {
            if (i == outTokenIdx) continue;
            if (txData[i].length == 0) continue;

            uint256 received = IERC20(tokens[i]).balanceOf(address(this)) - balancesBefore[i];
            if (received == 0) continue;

            IERC20(tokens[i]).forceApprove(router, received);
            (bool success, ) = router.call(txData[i]);
            if (!success) revert RouterFailure();
        }

        // 6. Calculate totalOut, check slippage, and send to user.
        totalOut = IERC20(outToken).balanceOf(address(this)) - balancesBefore[outTokenIdx];
        if (totalOut < minOutAmount) {
            revert MinOutAmountNotMet();
        }
        TransferHelper.safeTransfer(outToken, msg.sender, totalOut);
    }
}
