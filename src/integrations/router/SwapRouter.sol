// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Auto165} from "Commons/ERC/Auto165.sol";
import {IRFTPayer, RFTPayer} from "Commons/Util/RFT.sol";
import {IBurveMultiSwap} from "../../multi/interfaces/IBurveMultiSwap.sol";
import {TransferHelper} from "../../TransferHelper.sol";

/// @notice Defines the swap route per closure.
struct Route {
    /// The exact input when positive. The exact output when negative. Note that this is a real value.
    int240 amountSpecified;
    /// The closure we choose to swap through.
    uint16 cid;
}

/// Swap Router. For handling multiple swaps over multiple closures.
contract SwapRouter is RFTPayer, Auto165 {
    error ExcessiveAmountIn(uint256 acceptable, uint256 actual);
    error InsufficientAmountOut(uint256 acceptable, uint256 actual);
    error ReentrancyAttempt();
    error UntrustedTokenRequest(address sender);

    // Transient state;
    bool transient tLocked;
    address transient tPayer;
    address transient tSwapper;

    /// @notice Prevents reentrancy by locking the contract during the call.
    ///         When locked all nonReentrant functions will revert.
    modifier nonReentrant {
        require(!tLocked, ReentrancyAttempt());
        tLocked = true;
        _;
        tLocked = false;
    }

    /// @notice Single hop token swap over multiple closures.
    /// @param swapper The address of the swapper.
    /// @param recipient The recipient of the outToken.
    /// @param inToken Token to swap in.
    /// @param outToken Token to swap out.
    /// @param amountLimit When positive the maximum amount in. When negative the minimum amount out. Note that this is a real value.
    /// @param routes Closure routes to swap over.
    /// @dev There is no input validation that routes are all exact input or exact output.
    /// Or that the amount limit appropriately matches. Correctness is the responsability of the caller.
    /// Exact In:  route amountSpecified values are positive, amountLimit is negative to check minimum amount out.
    /// Exact Out: route amountSpecified values are negative, amountLimit is positive to check maximum amount in.
    function swap(
        address swapper,
        address recipient,
        address inToken,
        address outToken,
        int256 amountLimit,
        Route[] calldata routes
    ) external nonReentrant returns (uint256 inAmount, uint256 outAmount) {
        // Update transient storage 
        tSwapper = swapper;
        tPayer = msg.sender;

        // Execute swaps
        for (uint256 i = 0; i < routes.length; ++i) {
            Route memory route = routes[i];

            (uint256 _inAmount, uint256 _outAmount) = IBurveMultiSwap(swapper)
                .swap(
                    address(this),
                    inToken,
                    outToken,
                    route.amountSpecified,
                    0,
                    route.cid
                );
            inAmount += _inAmount;
            outAmount += _outAmount;
        }

        // Check amount in
        if (amountLimit > 0) {
            uint256 maxIn = uint256(amountLimit);
            require(inAmount <= maxIn, ExcessiveAmountIn(maxIn, inAmount));
        }

        // Check amount out
        if (amountLimit < 0) {
            uint256 minOut = uint256(-amountLimit);
            require(
                outAmount >= minOut,
                InsufficientAmountOut(minOut, outAmount)
            );
        }

        // Transfer to the recipient
        if (outAmount > 0) {
            TransferHelper.safeTransfer(
                outToken,
                recipient,
                outAmount
            );
        }

        // Reset transient storage
        tSwapper = address(0x0);
        tPayer = address(0x0);
    }

    /// @inheritdoc IRFTPayer
    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata data
    ) external returns (bytes memory cbData) {
        require(msg.sender == tSwapper && tSwapper != address(0x0), UntrustedTokenRequest(msg.sender));

        for (uint256 i = 0; i < tokens.length; ++i) {
            int256 amount = requests[i];

            // Requested payment
            if (amount > 0) {
                address token = tokens[i];

                TransferHelper.safeTransferFrom(
                    token,
                    tPayer,
                    msg.sender,
                    uint256(amount)
                );
            }
        }
    }
}
