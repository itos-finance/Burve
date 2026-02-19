// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {RFTPayer} from "Commons/Util/RFT.sol";
import {Auto165} from "Commons/ERC/Auto165.sol";
import {SafeCast} from "Commons/Math/Cast.sol";
import {BurveLender} from "../lender/BurveLender.sol";
import {IBurveMultiValue} from "../../multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../multi/interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "../../multi/facets/ValueTokenFacet.sol";
import {IAdjustor} from "../adjustor/IAdjustor.sol";
import {MAX_TOKENS} from "../../multi/Constants.sol";
import {FullMath} from "../../FullMath.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";

/// @title BurveLooper
/// @notice Stateless orchestrator for leveraged Burve positions.
///         Iteratively deposits tokens into Burve, posts value as collateral in BurveLender,
///         borrows tokens, and re-deposits to achieve target leverage.
///         Also supports deleveraging (closing loops).
contract BurveLooper is RFTPayer, Auto165, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    BurveLender public immutable LENDER;

    /// @dev Transient storage for the pool address during RFT callbacks.
    address public transient _pool;

    // --- Errors ---
    error InvalidIterations();
    error InvalidPool();
    error InvalidToken();
    error InvalidCaller();
    error MinOutAmountNotMet();
    error NotPositionOwner();
    error ZeroAmount();

    // --- Events ---
    event LoopOpened(uint256 indexed positionId, address indexed user, uint256 totalValue, uint256 totalDebt, uint8 iterations);
    event LoopClosed(uint256 indexed positionId, address indexed user, uint256 outAmount);
    event LoopReduced(uint256 indexed positionId, uint256 reducedValue, uint256 outAmount);

    constructor(address lender) {
        LENDER = BurveLender(lender);
    }

    /// @notice One-click leveraged position via iterative borrow-deposit loop.
    /// @param pool The Burve diamond address.
    /// @param closureId The closure to add value to.
    /// @param inToken The token to deposit (must be a pool token).
    /// @param inAmount The amount of inToken to start with.
    /// @param iterations Number of borrow-deposit iterations (2-10).
    /// @return positionId The BurveLender position ID created.
    function openLoop(
        address pool,
        uint16 closureId,
        address inToken,
        uint256 inAmount,
        uint8 iterations
    ) external nonReentrant returns (uint256 positionId) {
        if (inAmount == 0) revert ZeroAmount();
        if (iterations < 1 || iterations > 10) revert InvalidIterations();

        _pool = pool;

        // Validate inToken is a pool token
        _validatePoolToken(pool, inToken);

        // Transfer tokens from user
        IERC20(inToken).safeTransferFrom(msg.sender, address(this), inAmount);

        // Approve pool for RFT callbacks
        IERC20(inToken).forceApprove(pool, type(uint256).max);

        // Iteration 0: Initial deposit into Burve
        uint256 depositAmount = inAmount;
        uint256 totalValue;
        uint256 totalDebt;

        // First deposit: addSingleForValue, receive value, post as collateral
        uint256 valueReceived = IBurveMultiValue(pool).addSingleForValue(
            address(this),
            closureId,
            inToken,
            SafeCast.toUint128(depositAmount),
            0, // no BGT
            0  // no min value
        );
        totalValue += valueReceived;

        // Approve BurveLender to transfer our value position
        ValueTokenFacet(pool).approve(
            address(LENDER),
            closureId,
            type(uint256).max,
            0
        );

        // Post initial value as collateral in BurveLender
        positionId = LENDER.depositCollateral(pool, closureId, valueReceived, 0);

        // Track the last value received for computing safe borrow amounts
        uint256 lastValueReceived = valueReceived;

        // Iterations 1..N: borrow, deposit, add collateral
        for (uint8 i = 1; i <= iterations; i++) {
            // Borrow 70% of the last value received (conservative to account for swap fees)
            uint256 borrowAmount = FullMath.mulDiv(lastValueReceived, 70e16, 1e18);
            if (borrowAmount == 0) break;

            // Borrow from BurveLender
            LENDER.borrow(positionId, inToken, borrowAmount);
            totalDebt += borrowAmount;

            // Deposit borrowed tokens into Burve
            depositAmount = borrowAmount;
            IERC20(inToken).forceApprove(pool, depositAmount);

            valueReceived = IBurveMultiValue(pool).addSingleForValue(
                address(this),
                closureId,
                inToken,
                SafeCast.toUint128(depositAmount),
                0,
                0
            );
            totalValue += valueReceived;
            lastValueReceived = valueReceived;

            // Add the new value as additional collateral via BurveLender
            ValueTokenFacet(pool).approve(
                address(LENDER),
                closureId,
                type(uint256).max,
                0
            );
            LENDER.addCollateral(positionId, valueReceived, 0);
        }

        // Transfer position ownership to the user
        // The position in BurveLender is already owned by this contract as msg.sender,
        // but since BurveLender stores msg.sender as borrower, we need the user to interact
        // through this contract. Instead, we update: the position borrower is this contract
        // but we track that the actual user is msg.sender.
        // NOTE: BurveLender should be modified to allow BurveLooper to create positions
        // on behalf of users. For now, BurveLooper must be the borrower.

        // Reset approvals
        IERC20(inToken).forceApprove(pool, 0);
        _pool = address(0);

        emit LoopOpened(positionId, msg.sender, totalValue, totalDebt, iterations);
    }

    /// @notice Fully close a leveraged position: repay all debt, withdraw, return tokens.
    /// @param positionId The BurveLender position ID to close.
    /// @param outToken The token to receive.
    /// @param minOutAmount Minimum output amount.
    /// @return outAmount The total tokens returned to the user.
    function closeLoop(
        uint256 positionId,
        address outToken,
        uint256 minOutAmount
    ) external nonReentrant returns (uint256 outAmount) {
        (address borrower, address pool, uint16 closureId,, uint256 depositedValue, uint256 depositedBgtValue) = LENDER.positions(positionId);
        if (borrower != msg.sender) revert NotPositionOwner();

        _pool = pool;

        address[] memory poolTokens = IBurveMultiSimplex(pool).getTokens();

        // Step 1: User repays all debt first
        // The user must have already approved this contract for each borrowed token
        for (uint256 i = 0; i < poolTokens.length; i++) {
            uint256 owed = LENDER.currentBorrow(positionId, poolTokens[i]);
            if (owed == 0) continue;
            IERC20(poolTokens[i]).safeTransferFrom(msg.sender, address(this), owed);
            IERC20(poolTokens[i]).forceApprove(address(LENDER), owed);
            LENDER.repay(positionId, poolTokens[i], owed);
        }

        // Step 2: Withdraw all collateral
        LENDER.withdrawCollateral(positionId, depositedValue, depositedBgtValue);

        // Step 3: Remove value from Burve
        uint256[MAX_TOKENS] memory minAmounts;
        IBurveMultiValue(pool).removeValue(
            address(this),
            closureId,
            uint128(depositedValue),
            uint128(depositedBgtValue),
            minAmounts
        );

        // Step 4: Send the outToken balance to user
        outAmount = IERC20(outToken).balanceOf(address(this));
        if (outAmount < minOutAmount) revert MinOutAmountNotMet();
        IERC20(outToken).safeTransfer(msg.sender, outAmount);

        // Send any remaining non-outToken balances back to user too
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (poolTokens[i] == outToken) continue;
            uint256 bal = IERC20(poolTokens[i]).balanceOf(address(this));
            if (bal > 0) {
                IERC20(poolTokens[i]).safeTransfer(msg.sender, bal);
            }
        }

        _pool = address(0);

        emit LoopClosed(positionId, msg.sender, outAmount);
    }

    /// @notice Partially deleverage a position.
    /// @param positionId The position to reduce.
    /// @param reduceValueBy Amount of value to remove.
    /// @param outToken The token to receive.
    /// @param minOutAmount Minimum output amount.
    /// @return outAmount The tokens returned.
    function reduceLoop(
        uint256 positionId,
        uint256 reduceValueBy,
        address outToken,
        uint256 minOutAmount
    ) external nonReentrant returns (uint256 outAmount) {
        (address borrower, address pool, uint16 closureId,,,) = LENDER.positions(positionId);
        if (borrower != msg.sender) revert NotPositionOwner();

        _pool = pool;

        // Withdraw partial collateral
        LENDER.withdrawCollateral(positionId, reduceValueBy, 0);

        // Remove partial value from Burve
        uint256[MAX_TOKENS] memory minAmounts;
        IBurveMultiValue(pool).removeValue(
            address(this),
            closureId,
            uint128(reduceValueBy),
            0,
            minAmounts
        );

        // Use received tokens to repay some debt
        address[] memory poolTokens = IBurveMultiSimplex(pool).getTokens();
        for (uint256 i = 0; i < poolTokens.length; i++) {
            uint256 bal = IERC20(poolTokens[i]).balanceOf(address(this));
            uint256 owed = LENDER.currentBorrow(positionId, poolTokens[i]);
            if (owed > 0 && bal > 0) {
                uint256 repayAmount = bal < owed ? bal : owed;
                IERC20(poolTokens[i]).forceApprove(address(LENDER), repayAmount);
                LENDER.repay(positionId, poolTokens[i], repayAmount);
            }
        }

        // Send remaining outToken to user
        outAmount = IERC20(outToken).balanceOf(address(this));
        if (outAmount < minOutAmount) revert MinOutAmountNotMet();
        if (outAmount > 0) {
            IERC20(outToken).safeTransfer(msg.sender, outAmount);
        }

        _pool = address(0);

        emit LoopReduced(positionId, reduceValueBy, outAmount);
    }

    /// @notice Estimate the result of a loop before executing.
    /// @param inAmount The starting amount.
    /// @param iterations Number of iterations.
    /// @return totalValue Estimated total value position.
    /// @return totalDebt Estimated total debt.
    /// @return leverage Estimated leverage (1e18 = 1x).
    function estimateLoop(
        address,
        uint16,
        address,
        uint256 inAmount,
        uint8 iterations
    ) external pure returns (uint256 totalValue, uint256 totalDebt, uint256 leverage) {
        // Simple geometric series estimation
        // Each iteration deposits 70% of previous value
        uint256 lastValue = inAmount;
        totalValue = inAmount; // approximate: 1 unit deposit ≈ 1 unit value

        for (uint8 i = 1; i <= iterations; i++) {
            uint256 borrowAmount = FullMath.mulDiv(lastValue, 70e16, 1e18);
            if (borrowAmount == 0) break;
            totalDebt += borrowAmount;
            totalValue += borrowAmount;
            lastValue = borrowAmount;
        }

        leverage = totalValue > 0 ? FullMath.mulDiv(totalValue, 1e18, inAmount) : 0;
    }

    // ============================================================
    //                     RFT CALLBACK
    // ============================================================

    /// @notice RFT callback: pays requested tokens to the Burve pool during addValue/addSingleForValue.
    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata
    ) external returns (bytes memory) {
        require(msg.sender == _pool, InvalidCaller());

        for (uint256 i = 0; i < tokens.length; i++) {
            if (requests[i] > 0) {
                TransferHelper.safeTransfer(
                    tokens[i],
                    msg.sender,
                    SafeCast.toUint256(requests[i])
                );
            }
        }
    }

    // ============================================================
    //                     INTERNAL
    // ============================================================

    function _validatePoolToken(address pool, address token) internal view {
        address[] memory tokens = IBurveMultiSimplex(pool).getTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) return;
        }
        revert InvalidToken();
    }
}
