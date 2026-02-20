// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {RFTPayer} from "Commons/Util/RFT.sol";
import {Auto165} from "Commons/ERC/Auto165.sol";
import {SafeCast} from "Commons/Math/Cast.sol";
import {IBurveMultiValue} from "../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "../../src/multi/facets/ValueTokenFacet.sol";
import {Lender} from "../../src/integrations/lender/Lender.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PositionHelper
/// @notice Helper contract for creating Burve positions from a script.
///         Implements RFTPayer so it can call addValue on the diamond.
///         Deployed once, then used to create positions for any user.
contract PositionHelper is RFTPayer, Auto165 {
    using SafeERC20 for IERC20;

    address public immutable diamond;
    address public immutable owner;

    /// @dev Transient storage for the pool address during RFT callbacks.
    address public transient _pool;

    constructor(address _diamond) {
        diamond = _diamond;
        owner = msg.sender;
    }

    /// @notice Create a value position and deposit as collateral in Lender.
    /// @param lender The Lender address.
    /// @param closureId The closure to deposit into.
    /// @param value The value units to add.
    /// @param borrowToken The token to borrow (or address(0) for no borrow).
    /// @param ltvPercent The LTV percentage to borrow at (0-80).
    /// @return positionId The Lender position ID.
    function createPosition(
        address lender,
        uint16 closureId,
        uint128 value,
        address borrowToken,
        uint256 ltvPercent
    ) external returns (uint256 positionId) {
        require(msg.sender == owner, "only owner");

        _pool = diamond;

        address[] memory tokens = IBurveMultiSimplex(diamond).getTokens();

        // Approve diamond for all closure tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            if ((1 << i) & closureId > 0) {
                IERC20(tokens[i]).forceApprove(diamond, type(uint256).max);
            }
        }

        // Add value to Burve — this triggers RFT callback
        uint256[MAX_TOKENS] memory limits;
        IBurveMultiValue(diamond).addValue(address(this), closureId, value, 0, limits);

        // Get our value balance
        (uint256 posValue, ) = ValueTokenFacet(diamond).balanceOf(address(this), closureId);

        // Approve Lender and deposit as collateral
        ValueTokenFacet(diamond).approve(lender, closureId, posValue, 0);
        positionId = Lender(lender).depositCollateral(diamond, closureId, posValue, 0);

        // Borrow if requested
        if (ltvPercent > 0 && borrowToken != address(0)) {
            uint256 colUSD = Lender(lender).collateralValueUSD(positionId);
            uint256 borrowAmount = (colUSD * ltvPercent) / 100;
            if (borrowAmount > 0) {
                Lender(lender).borrow(positionId, borrowToken, borrowAmount);
                // Send borrowed tokens back to owner
                uint256 bal = IERC20(borrowToken).balanceOf(address(this));
                if (bal > 0) {
                    IERC20(borrowToken).safeTransfer(owner, bal);
                }
            }
        }

        _pool = address(0);
    }

    /// @notice RFT callback: pays requested tokens to the Burve pool.
    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata
    ) external returns (bytes memory ret) {
        require(msg.sender == _pool, "invalid caller");
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
}
