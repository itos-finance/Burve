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
        // Updated by deposit/withdraw hooks
        uint256 trackedShares;
        // These are updated by claim rewards
        uint40 lastTimestamp;
        uint40 pausedSecondsCheckpoint;
        // Updated when users claim rewards
        uint256 owed;
    }

    IERC20 public immutable rewardToken; // e.g. WBERA
    address public immutable brc20;

    // Emission rate per hour per share in X64 fixed point (tokensPerHourPerShareX64)
    uint256 public tokensPerHourPerShareX64;

    mapping(address => Account) public accounts;

    // Simplified reward tracking at rewarder level
    uint256 public totalClaimedRewards; // Total claimed rewards across all users
    bool public accumulationPaused;

    uint256 public totalShares; // Total shares across all users

    // These can only be modified by _updateRewards
    uint40 public lastUpdateTimestamp; // Last time rewards were updated
    uint40 private pausedSeconds; // Track the time we were paused for since the beginning
    uint256 public totalUnclaimedRewards; // Total unclaimed rewards across all users

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

    function updateRewards() external {
        _updateRewards();
    }

    /// @notice Users can claim without changing position.
    /// This doesn't actually remove any reward tokens yet.
    function claim() external {
        _updateRewards();
        _claimRewards(msg.sender);
    }

    /// @notice Actually removed all the accumulated rewards
    function withdrawRewards() external {
        _updateRewards();
        _claimRewards(msg.sender);
        _withdrawRewards(msg.sender);
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
        if (accumulationPaused || lastUpdateTimestamp == 0) {
            return totalUnclaimedRewards;
        }

        uint256 elapsed = block.timestamp - uint256(lastUpdateTimestamp);
        if (elapsed > 0) {
            // Calculate new rewards: (totalShares * ratePerHourX64 * elapsed / 3600) >> 64
            uint256 perSecondX64 = tokensPerHourPerShareX64 / 3600;
            uint256 owedPerSecondX64 = totalShares * perSecondX64;
            uint256 newRewards = (owedPerSecondX64 * elapsed) >> 64;
            return totalUnclaimedRewards + newRewards;
        }
        return totalUnclaimedRewards;
    }

    /// @notice Check if accumulation should be paused based on available balance
    function shouldPauseAccumulation() public view returns (bool) {
        uint256 availableBalance = rewardToken.balanceOf(address(this));
        return calculateTotalUnclaimedRewards() > availableBalance;
    }

    /// @notice Resume accumulation (admin only)
    function pauseAccumulation() external {
        AdminLib.validateOwner();
        _updateRewards();
        _pause();
    }

    /// @notice Resume accumulation (admin only)
    function resumeAccumulation() external {
        AdminLib.validateOwner();
        _unpause();
    }

    // --------------------
    // Internal Functions
    // --------------------

    /// @notice Update global reward tracking
    function _updateRewards() internal {
        if (lastUpdateTimestamp == uint40(block.timestamp)) return;

        // If we are paused, there's nothing to accumulate since the last timestamp (the time of pause).
        if (accumulationPaused) {
            // Just update the pausedSeconds checkpoint
            pausedSeconds += uint40(block.timestamp) - lastUpdateTimestamp;
            lastUpdateTimestamp = uint40(block.timestamp);
            emit RewardsUpdated(
                totalUnclaimedRewards,
                totalClaimedRewards,
                block.timestamp
            );
            return;
        }

        if (totalShares > 0) {
            uint256 elapsed = block.timestamp - uint256(lastUpdateTimestamp);
            if (elapsed > 0) {
                // Calculate new rewards: totalShares * ratePerHourX64 >> 64 * elapsed / 3600
                uint256 perSecondX64 = tokensPerHourPerShareX64 / 3600;
                uint256 owedPerSecondX64 = totalShares * perSecondX64;
                uint256 newRewards = (owedPerSecondX64 * elapsed) >> 64;
                totalUnclaimedRewards += newRewards;
                lastUpdateTimestamp = uint40(block.timestamp);
            }
        }

        // Check if we should pause accumulation
        if (_shouldPauseAccumulation()) {
            _pause();
        }

        emit RewardsUpdated(
            totalUnclaimedRewards,
            totalClaimedRewards,
            block.timestamp
        );
    }

    /// @notice Claim rewards for a specific user
    /// @dev MUST be called after _updateRewards to ensure up-to-date state.
    function _claimRewards(address user) internal {
        Account storage a = accounts[user];
        uint256 pending = 0;
        // We always want to update the timestamp so addShares/removeShares can verify
        // that the rewards have been updated already.
        if (a.trackedShares > 0) {
            pending = _calculateUserPendingRewards(a);
        }
        a.owed += pending;

        // Update user's last timestamp to current time
        a.lastTimestamp = uint40(block.timestamp);
        a.pausedSecondsCheckpoint = pausedSeconds;
    }

    /// @notice Withdraw rewards for a specific user (as much as possible).
    function _withdrawRewards(address user) internal {
        // Try to pay out rewards
        uint256 availableBalance = rewardToken.balanceOf(address(this));
        Account storage a = accounts[user];
        uint256 toPay = a.owed > availableBalance ? availableBalance : a.owed;

        if (toPay > 0) {
            TransferHelper.safeTransfer(address(rewardToken), user, toPay);
            totalClaimedRewards += toPay;
            totalUnclaimedRewards -= toPay;
            a.owed -= toPay;
            emit RewardsClaimed(user, toPay);
        }
    }

    /// @notice Add shares to a user's account
    /// @dev you must update account rewards before this.
    function _addShares(address user, uint256 shares) internal {
        if (shares == 0) return;

        Account storage a = accounts[user];
        // This must have been updated already.
        require(a.lastTimestamp == uint40(block.timestamp));
        a.trackedShares += shares;
        totalShares += shares;
        emit SharesUpdated(user, a.trackedShares, block.timestamp);
    }

    /// @notice Remove shares from a user's account
    function _removeShares(address user, uint256 shares) internal {
        if (shares == 0) return;

        Account storage a = accounts[user];
        // This must have had its rewards updated already.
        require(a.lastTimestamp == uint40(block.timestamp));
        uint256 toRemove = shares > a.trackedShares ? a.trackedShares : shares;

        if (toRemove > 0) {
            a.trackedShares -= toRemove;
            totalShares -= toRemove;
            emit SharesUpdated(user, a.trackedShares, block.timestamp);
        }
    }

    /// @notice Calculate pending rewards for a specific account
    function _calculateUserPendingRewards(
        Account storage a
    ) internal view returns (uint256) {
        if (a.trackedShares == 0) return 0;

        // See how much time it has been since their last update, minus any paused time.
        uint256 elapsed = uint40(block.timestamp) -
            a.lastTimestamp -
            pausedSeconds +
            a.pausedSecondsCheckpoint;
        if (elapsed == 0) return 0;

        uint256 perSecondX64 = tokensPerHourPerShareX64 / 3600;
        uint256 owedPerSecondX64 = a.trackedShares * perSecondX64;
        uint256 userPendingRewards = (owedPerSecondX64 * elapsed) >> 64;

        return userPendingRewards;
    }

    /// @notice Check if accumulation should be paused
    function _shouldPauseAccumulation() internal view returns (bool) {
        uint256 availableBalance = rewardToken.balanceOf(address(this));
        return totalUnclaimedRewards > availableBalance;
    }

    function _pause() internal {
        if (accumulationPaused) return;
        // If we haven't updated rewards yet we have to do it now before the pause.
        if (lastUpdateTimestamp != uint40(block.timestamp)) {
            _updateRewards();
        }
        accumulationPaused = true;
        uint256 availableBalance = rewardToken.balanceOf(address(this));
        emit AccumulationPaused(totalUnclaimedRewards, availableBalance);
    }

    function _unpause() internal {
        if (!accumulationPaused) return;
        // Updates the paused seconds and resets the timestamp to now.
        if (lastUpdateTimestamp != uint40(block.timestamp)) {
            _updateRewards();
        }
        accumulationPaused = false;
        emit AccumulationResumed();
    }
}
