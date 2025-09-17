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

    IERC20 public immutable rewardToken; // e.g. WBERA
    address public immutable brc20;

    // Emission rate per hour per share in X64 fixed point (tokensPerHourPerShareX64)
    uint256 public tokensPerHourPerShareX64;

    mapping(address => Account) public accounts;

    // Simplified reward tracking at rewarder level
    uint256 public totalUnclaimedRewards; // Total unclaimed rewards across all users
    uint256 public totalClaimedRewards; // Total claimed rewards across all users
    bool public accumulationPaused;

    uint256 public totalShares; // Total shares across all users
    uint40 public lastUpdateTimestamp; // Last time rewards were updated

    event Funded(address indexed funder, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event RateUpdated(uint256 newRateX64);
    event AccumulationPaused(uint256 totalUnclaimed, uint256 availableBalance);
    event AccumulationResumed();
    event RewardsUpdated(
        uint256 totalUnclaimed,
        uint256 totalClaimed,
        uint256 timestamp
    );
    event RewardsClaimed(address indexed user, uint256 amount);
    event SharesUpdated(
        address indexed user,
        uint256 newShares,
        uint256 timestamp
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
        lastUpdateTimestamp = uint40(block.timestamp);
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

        // Check if we can resume accumulation after funding
        if (accumulationPaused && !_shouldPauseAccumulation()) {
            accumulationPaused = false;
            emit AccumulationResumed();
        }

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
        _updateRewards();
        _claimRewards(user);
        _addShares(user, mintedShares);
    }

    /// @notice Called by BRC20 before shares are burned. Settles based on full tracked shares, then decrements.
    function onWithdraw(
        address user,
        uint256 requestedSharesToBurn
    ) external onlyBRC20 {
        _updateRewards();
        _claimRewards(user);
        _removeShares(user, requestedSharesToBurn);
    }

    /// @notice Users can claim without changing position.
    function claim() external {
        _updateRewards();
        _claimRewards(msg.sender);
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

        if (a.trackedShares == 0 || a.lastTimestamp == 0) {
            return (0, trackedShares, lastTimestamp);
        }

        pending = _calculateUserPendingRewards(a);
    }

    /// @notice Calculate total unclaimed rewards across all users
    function calculateTotalUnclaimedRewards()
        public
        view
        returns (uint256 total)
    {
        return totalUnclaimedRewards;
    }

    /// @notice Check if accumulation should be paused based on available balance
    function shouldPauseAccumulation() public view returns (bool) {
        uint256 availableBalance = rewardToken.balanceOf(address(this));
        return totalUnclaimedRewards > availableBalance;
    }

    /// @notice Resume accumulation (admin only)
    function resumeAccumulation() external {
        AdminLib.validateOwner();
        accumulationPaused = false;
        emit AccumulationResumed();
    }

    // --------------------
    // Internal Functions
    // --------------------

    /// @notice Update global reward tracking
    function _updateRewards() internal {
        if (lastUpdateTimestamp == uint40(block.timestamp)) return;

        if (lastUpdateTimestamp > 0 && totalShares > 0 && !accumulationPaused) {
            uint256 elapsed = block.timestamp - uint256(lastUpdateTimestamp);
            if (elapsed > 0) {
                // Calculate new rewards: totalShares * ratePerHourX64 >> 64 * elapsed / 3600
                uint256 perSecondX64 = tokensPerHourPerShareX64 / 3600;
                uint256 owedPerSecond = (totalShares * perSecondX64) >> 64;
                uint256 newRewards = owedPerSecond * elapsed;
                totalUnclaimedRewards += newRewards;
            }
        }

        // Check if we should pause accumulation
        if (!accumulationPaused && _shouldPauseAccumulation()) {
            accumulationPaused = true;
            uint256 availableBalance = rewardToken.balanceOf(address(this));
            emit AccumulationPaused(totalUnclaimedRewards, availableBalance);
        }

        lastUpdateTimestamp = uint40(block.timestamp);
        emit RewardsUpdated(
            totalUnclaimedRewards,
            totalClaimedRewards,
            block.timestamp
        );
    }

    /// @notice Claim rewards for a specific user
    function _claimRewards(address user) internal {
        Account memory a = accounts[user];
        if (a.trackedShares == 0 || a.lastTimestamp == 0) return;

        uint256 pending = _calculateUserPendingRewards(a);
        if (pending == 0) return;

        // Update user's last timestamp to current time
        a.lastTimestamp = uint40(block.timestamp);
        accounts[user] = a;

        // Try to pay out rewards
        uint256 availableBalance = rewardToken.balanceOf(address(this));
        uint256 toPay = pending > availableBalance ? availableBalance : pending;

        if (toPay > 0) {
            TransferHelper.safeTransfer(address(rewardToken), user, toPay);
            totalClaimedRewards += toPay;
            totalUnclaimedRewards -= toPay;
            emit RewardsClaimed(user, toPay);
        }

        // If we couldn't pay the full amount, close the position
        if (toPay < pending) {
            totalShares -= a.trackedShares;
            a.trackedShares = 0;
            a.lastTimestamp = 0;
            accounts[user] = a;
        }
    }

    /// @notice Add shares to a user's account
    function _addShares(address user, uint256 shares) internal {
        if (shares == 0) return;

        Account memory a = accounts[user];
        a.trackedShares += shares;
        a.lastTimestamp = uint40(block.timestamp);
        accounts[user] = a;

        totalShares += shares;
        emit SharesUpdated(user, a.trackedShares, block.timestamp);
    }

    /// @notice Remove shares from a user's account
    function _removeShares(address user, uint256 shares) internal {
        if (shares == 0) return;

        Account memory a = accounts[user];
        uint256 toRemove = shares > a.trackedShares ? a.trackedShares : shares;

        if (toRemove > 0) {
            a.trackedShares -= toRemove;
            totalShares -= toRemove;

            if (a.trackedShares == 0) {
                a.lastTimestamp = 0;
            } else {
                a.lastTimestamp = uint40(block.timestamp);
            }

            accounts[user] = a;
            emit SharesUpdated(user, a.trackedShares, block.timestamp);
        }
    }

    /// @notice Calculate pending rewards for a specific account
    function _calculateUserPendingRewards(
        Account memory a
    ) internal view returns (uint256) {
        if (a.trackedShares == 0 || a.lastTimestamp == 0) return 0;

        uint256 elapsed = block.timestamp - uint256(a.lastTimestamp);
        if (elapsed == 0) return 0;

        // If accumulation is paused, return 0 for new pending rewards
        if (accumulationPaused) return 0;

        // Calculate rewards from user's lastTimestamp to current block timestamp
        // This simulates the collection of rewards up to the current time
        uint256 perSecondX64 = tokensPerHourPerShareX64 / 3600;
        uint256 owedPerSecond = (a.trackedShares * perSecondX64) >> 64;
        uint256 userPendingRewards = owedPerSecond * elapsed;

        return userPendingRewards;
    }

    /// @notice Check if accumulation should be paused
    function _shouldPauseAccumulation() internal view returns (bool) {
        uint256 availableBalance = rewardToken.balanceOf(address(this));
        return totalUnclaimedRewards > availableBalance;
    }
}
