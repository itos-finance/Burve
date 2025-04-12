// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IBGTExchanger} from "./IBGTExchanger.sol";
import {FullMath} from "../../FullMath.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {AdminLib} from "Commons/Util/Admin.sol";

contract BGTExchanger is IBGTExchanger {
    mapping(address token => uint256 rateX128) public rate;
    mapping(address caller => uint256) public owed;
    mapping(address caller => bool) public isExchanger;
    address public bgtToken;
    uint256 public bgtBalance;
    IBgtExchanger public backupEx;

    error NoExchangePermissions();
    error InsufficientOwed();

    constructor() {
        AdminLib.initOwner(msg.sender);
    }

    /// @inheritdoc IBGTExchanger
    function exchange(
        address inToken,
        uint128 amount
    ) external returns (uint256 bgtAmount, uint256 spendAmount) {
        if (!isExchanger[msg.sender]) revert NoExchangePermissions();

        // If rate is zero, the spendAmount remains zero.
        bgtAmount = FullMath.mulX128(rate[inToken], amount, false);
        if (bgtBalance < bgtAmount) {
            bgtAmount = bgtBalance;
            // Rate won't be zero here or else bgtAmount is 0 and can't be more.
            amount = uint128(
                FullMath.mulDivRoundingUp(bgtAmount, 1 << 128, rate[inToken])
            );
        }
        if (bgtAmount != 0) {
            bgtBalance -= bgtAmount;
            TransferHelper.safeTransferFrom( // We take what we need.
                    inToken,
                    msg.sender,
                    address(this),
                    amount
                );
            owed[msg.sender] += bgtAmount;
            spendAmount = amount;
        }
    }

    /// @inheritdoc IBGTExchanger
    function withdraw(address recipient, uint256 bgtAmount) external {
        if (owed[msg.sender] < bgtAmount) revert InsufficientOwed();
        owed[msg.sender] -= bgtAmount;
        TransferHelper.safeTransfer(bgtToken, recipient, bgtAmount);
    }

    /* Admin Functions */
    /// @inheritdoc IBGTExchanger
    function addExchanger(address caller) external {
        AdminLib.validateOwner();
        isExchanger[caller] = true;
    }

    /// @inheritdoc IBGTExchanger
    function removeExchanger(address caller) external {
        AdminLib.validateOwner();
        isExchanger[caller] = false;
    }

    /// @inheritdoc IBGTExchanger
    function setRate(address inToken, uint256 rateX128) external {
        AdminLib.validateOwner();
        rate[inToken] = rateX128;
    }

    /// @inheritdoc IBGTExchanger
    function sendBalance(address token, address to, uint256 amount) external {
        AdminLib.validateOwner();
        TransferHelper.safeTransfer(token, to, amount);
    }

    /// @inheritdoc IBGTExchanger
    function fund(uint256 amount) external {
        TransferHelper.safeTransferFrom(
            bgtToken,
            msg.sender,
            address(this),
            amount
        );
    }

    // TODO add to standard
    function setBackup(address backup) external {
        AdminLib.validateOwner();
        backupEx = IBGTExchanger(backup);
    }

    // TODO add to standard.
    function getOwed() external returns (uint256 _owed) {
        _owed = owed[msg.sender];
        if (address(backupEx) != address(0)) {
            backupEx.getOwed(msg.sender);
        }
    }
}
