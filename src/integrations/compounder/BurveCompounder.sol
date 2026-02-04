// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IRFTPayer} from "Commons/Util/RFT.sol";
import {IERC165} from "Commons/ERC/interfaces/IERC165.sol";
import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IBurveMultiValue} from "../../multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../multi/interfaces/IBurveMultiSimplex.sol";
import {MAX_TOKENS} from "../../multi/Constants.sol";

struct SingleDeposit {
    address token;
    uint128 amount;
    uint128 minValue;
}

contract BurveCompounder is IRFTPayer, IERC165 {
    address public immutable diamond;

    error OnlyDiamond();

    constructor(address _diamond) {
        diamond = _diamond;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IRFTPayer).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Collect earnings and re-deposit them into the same closure.
    /// @param closureId The closure to compound.
    /// @param addValueAmount Value param for addValue (0 to skip proportional deposit).
    /// @param addValueLimits Max token amounts for addValue.
    /// @param singleDeposits Per-token deposits for leftover amounts.
    function compound(
        uint16 closureId,
        uint128 addValueAmount,
        uint256[MAX_TOKENS] calldata addValueLimits,
        SingleDeposit[] calldata singleDeposits
    ) external {
        // 1. Collect earnings to this contract
        IBurveMultiValue(diamond).collectEarnings(address(this), closureId);

        // 2. Proportional deposit if requested
        if (addValueAmount > 0) {
            IBurveMultiValue(diamond).addValue(
                msg.sender,
                closureId,
                addValueAmount,
                0, // no BGT
                addValueLimits
            );
        }

        // 3. Single-token deposits for remaining balances
        for (uint256 i = 0; i < singleDeposits.length; i++) {
            SingleDeposit calldata dep = singleDeposits[i];
            if (dep.amount > 0) {
                IBurveMultiValue(diamond).addSingleForValue(
                    msg.sender,
                    closureId,
                    dep.token,
                    dep.amount,
                    0, // no BGT
                    dep.minValue
                );
            }
        }

        // 4. Return dust to caller
        address[] memory poolTokens = IBurveMultiSimplex(diamond).getTokens();
        for (uint256 i = 0; i < poolTokens.length; i++) {
            uint256 bal = IERC20(poolTokens[i]).balanceOf(address(this));
            if (bal > 0) {
                TransferHelper.safeTransfer(poolTokens[i], msg.sender, bal);
            }
        }
    }

    /// @notice RFT callback — transfer positive-requested amounts to the diamond.
    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata
    ) external override returns (bytes memory) {
        if (msg.sender != diamond) revert OnlyDiamond();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (requests[i] > 0) {
                TransferHelper.safeTransfer(tokens[i], diamond, uint256(requests[i]));
            }
        }
        return "";
    }
}
