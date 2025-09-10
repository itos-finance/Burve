// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {AdminLib} from "Commons/Util/Admin.sol";

/// @title Rewarder2 - Single-token, time-based reward distribution per BRC20 share
/// @notice Pays a fixed emission rate per hour per tracked share. Tracks user shares and last accrual timestamp.
contract Rewarder2 {
    struct Account {
        uint256 trackedShares;
        uint40 lastTimestamp;
    }

    IERC20 public immutable rewardToken; // e.g., BERA (or WBERA)
    address public immutable brc20;

    // Emission rate per hour per share in X64 fixed point (tokensPerHourPerShareX64)
    uint256 public tokensPerHourPerShareX64;

    mapping(address => Account) public accounts;

    event Funded(address indexed funder, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event RateUpdated(uint256 newRateX64);
    event Settled(
        address indexed user,
        uint256 paid,
        uint256 newTrackedShares,
        uint256 newTimestamp
    );

    constructor(
        address _brc20,
        address _rewardToken,
        uint256 _tokensPerHourPerShareX64
    ) {
        AdminLib.initOwner(msg.sender);
        brc20 = _brc20;
        rewardToken = IERC20(_rewardToken);
        tokensPerHourPerShareX64 = _tokensPerHourPerShareX64;
    }

    // --------------------
    // Admin
    // --------------------
    function setRatePerHourPerShareX64(uint256 newRateX64) external {
        AdminLib.validateOwner();
        tokensPerHourPerShareX64 = newRateX64;
        emit RateUpdated(newRateX64);
    }

    function fund(uint256 amount) external {
        AdminLib.validateOwner();
        if (amount == 0) return;
        TransferHelper.safeTransferFrom(
            address(rewardToken),
            msg.sender,
            address(this),
            amount
        );
        emit Funded(msg.sender, amount);
    }

    function withdraw(uint256 amount, address to) external {
        AdminLib.validateOwner();
        if (amount == 0) return;
        TransferHelper.safeTransfer(address(rewardToken), to, amount);
        emit Withdrawn(to, amount);
    }

    // --------------------
    // BRC20 hooks
    // --------------------
    modifier onlyBRC20() {
        require(msg.sender == brc20, "Only BRC20");
        _;
    }

    /// @notice Called by BRC20 after shares are minted. Also settles any pending rewards up to now.
    function onDeposit(address user, uint256 mintedShares) external onlyBRC20 {
        _settle(user, true, mintedShares, 0);
    }

    /// @notice Called by BRC20 before shares are burned. Settles based on full tracked shares, then decrements.
    function onWithdraw(
        address user,
        uint256 requestedSharesToBurn
    ) external onlyBRC20 {
        _settle(user, false, 0, requestedSharesToBurn);
    }

    /// @notice Users can claim without changing position. Useful after rewarder replacement.
    function claim() external {
        _settle(msg.sender, false, 0, 0);
    }

    function viewPending(
        address user
    )
        external
        view
        returns (uint256 pending, uint256 trackedShares, uint256 lastTimestamp)
    {
        Account memory a = accounts[user];
        trackedShares = a.trackedShares;
        lastTimestamp = a.lastTimestamp;
        if (a.trackedShares == 0 || a.lastTimestamp == 0)
            return (0, trackedShares, lastTimestamp);
        uint256 elapsed = block.timestamp - uint256(a.lastTimestamp);
        if (elapsed == 0) return (0, trackedShares, lastTimestamp);
        // owed = shares * ratePerHourX64 >> 64 * elapsed / 3600
        uint256 perSecondX64 = tokensPerHourPerShareX64 / 3600;
        uint256 owed = (a.trackedShares * perSecondX64) >> 64;
        pending = owed * elapsed;
    }

    // --------------------
    // Internal
    // --------------------
    function _settle(
        address user,
        bool isDeposit,
        uint256 mintedShares,
        uint256 requestedBurnShares
    ) internal {
        Account memory a = accounts[user];
        uint256 paid;

        if (a.trackedShares > 0 && a.lastTimestamp != 0) {
            uint256 elapsed = block.timestamp - uint256(a.lastTimestamp);
            if (elapsed > 0) {
                // owed = shares * ratePerHourX64 >> 64 * elapsed / 3600
                uint256 perSecondX64 = tokensPerHourPerShareX64 / 3600;
                uint256 owedPerSecond = (a.trackedShares * perSecondX64) >> 64;
                uint256 owed = owedPerSecond * elapsed;

                uint256 bal = rewardToken.balanceOf(address(this));
                if (bal < owed) {
                    if (bal > 0) {
                        TransferHelper.safeTransfer(
                            address(rewardToken),
                            user,
                            bal
                        );
                        paid = bal;
                    }
                    // Close the position if underfunded
                    a.trackedShares = 0;
                    a.lastTimestamp = 0;
                    accounts[user] = a;
                    emit Settled(user, paid, a.trackedShares, a.lastTimestamp);
                    return;
                } else {
                    if (owed > 0) {
                        TransferHelper.safeTransfer(
                            address(rewardToken),
                            user,
                            owed
                        );
                        paid = owed;
                    }
                }
            }
        }

        if (isDeposit) {
            // Increase tracked shares and reset timestamp
            if (mintedShares > 0) {
                a.trackedShares += mintedShares;
            }
            a.lastTimestamp = uint40(block.timestamp);
        } else {
            if (requestedBurnShares > 0) {
                uint256 burn = requestedBurnShares > a.trackedShares
                    ? a.trackedShares
                    : requestedBurnShares;
                a.trackedShares -= burn;
            }
            if (a.trackedShares == 0) {
                a.lastTimestamp = 0;
            } else {
                a.lastTimestamp = uint40(block.timestamp);
            }
        }

        accounts[user] = a;
        emit Settled(user, paid, a.trackedShares, a.lastTimestamp);
    }
}
