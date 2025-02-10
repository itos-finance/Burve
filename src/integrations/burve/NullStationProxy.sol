// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStationProxy} from "./IStationProxy.sol";
import {TransferHelper} from "../../TransferHelper.sol";

contract NullStationProxy is IStationProxy {
    mapping(address sender => mapping(address lp => mapping(address owner => uint256 balance))) allowances;
    // Typically a station proxy will also have owner => lp token => amounts + checkpoints to be able to claim rewards.

    // Do nothing.
    function harvest() external {}

    /// @inheritdoc IStationProxy
    function depositLP(
        address lpToken,
        uint256 amount,
        address owner
    ) external {
        TransferHelper.safeTransferFrom(
            lpToken,
            msg.sender,
            address(this),
            amount
        );
        allowances[msg.sender][lpToken][owner] += amount;
    }

    /// @inheritdoc IStationProxy
    function withdrawLP(
        address lpToken,
        uint256 amount,
        address owner
    ) external {
        allowances[msg.sender][lpToken][owner] += amount;
        TransferHelper.safeTransfer(lpToken, msg.sender, amount);
    }
}
