// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {BurveForkableTest} from "../../test/integrations/Fork.u.sol";
import {Rewarder2} from "../../src/integrations/Rewarder2.sol";
import {BRC20} from "../../src/integrations/BRC20.sol";

contract FRewarder2Base is BurveForkableTest {
    address constant OMNIPOOL = 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;
    address constant WBERA = 0x6969696969696969696969696969696969696969;

    function testFRewarder2BasicAccrual() public forkOnly {
        // Deploy BRC20 and Rewarder2
        BRC20 brc20 = new BRC20(
            "Burve BRC20",
            "bBRC20",
            OMNIPOOL,
            3,
            address(0),
            0
        );
        Rewarder2 rewarder = new Rewarder2(address(brc20), WBERA, 1 << 64); // 1 token/hour/share

        // Wire rewarder into BRC20 (owner is deployer in ctor)
        brc20.setRewarder(address(rewarder));

        // Fund rewarder
        deal(WBERA, address(this), 1000e18);
        IERC20(WBERA).approve(address(rewarder), type(uint256).max);
        rewarder.fund(1000e18);

        address user = address(this);

        // Simulate a deposit of 1e18 shares via BRC20 hook
        vm.prank(address(brc20));
        rewarder.onDeposit(user, 1e18);

        // Accrue for 1 hour
        uint256 beforeBal = IERC20(WBERA).balanceOf(user);
        vm.warp(block.timestamp + 3600);

        // Withdraw half of the position (should pay on full trackedShares prior to change)
        vm.prank(address(brc20));
        rewarder.onWithdraw(user, 5e17);

        rewarder.withdrawRewards();
        uint256 afterBal = IERC20(WBERA).balanceOf(user);

        // Expect ~1e18 tokens (1 token/hour/share * 1e18 shares * 1 hour)
        assertApproxEqAbs(afterBal - beforeBal, 1e18, 1e6);
    }

    function testFRewarder2UnderfundingCloses() public forkOnly {
        Rewarder2 rewarder = new Rewarder2(address(0xBEEF), WBERA, 10 << 64); // use dummy brc20 for prank

        // Fund with small amount
        deal(WBERA, address(this), 5e18);
        IERC20(WBERA).approve(address(rewarder), type(uint256).max);
        rewarder.fund(5e18);

        address user = address(0xBEEF);

        // Deposit large shares
        vm.prank(address(0xBEEF));
        rewarder.onDeposit(user, 100e18);

        vm.warp(block.timestamp + 3600); // 1 hour

        // This would owe 100e18 * 10 = 1000e18, but only 5e18 funded
        uint256 beforeBal = IERC20(WBERA).balanceOf(user);
        vm.prank(address(0xBEEF));
        rewarder.onWithdraw(user, 10e18);
        uint256 afterBal = IERC20(WBERA).balanceOf(user);

        // Paid capped by fund (5e18), and position closed
        assertEq(afterBal - beforeBal, 5e18);
        (uint256 pending, , ) = rewarder.viewPending(user);
        assertEq(pending, 0);
    }

    function testFRewarder2UnderfundingNoError() public forkOnly {
        // Deploy BRC20 and Rewarder2
        BRC20 brc20 = new BRC20(
            "Burve BRC20",
            "bBRC20",
            OMNIPOOL,
            3,
            address(0),
            0
        );
        Rewarder2 rewarder = new Rewarder2(address(brc20), WBERA, 1 << 64); // 1 token/hour/share

        // Wire rewarder into BRC20
        brc20.setRewarder(address(rewarder));

        // Fund with very small amount
        deal(WBERA, address(this), 1e18);
        IERC20(WBERA).approve(address(rewarder), type(uint256).max);
        rewarder.fund(1e18);

        address user = address(this);

        // Deposit large amount of shares
        vm.prank(address(brc20));
        rewarder.onDeposit(user, 1000e18);

        // Wait a long time to accrue more rewards than available
        vm.warp(block.timestamp + 7200); // 2 hours

        // Check pending rewards (should be much more than available)
        (uint256 pending, uint256 trackedShares, ) = rewarder.viewPending(user);
        console2.log("Pending rewards:", pending);
        console2.log(
            "Available balance:",
            IERC20(WBERA).balanceOf(address(rewarder))
        );
        console2.log("Tracked shares:", trackedShares);

        // This should NOT revert even though pending > available balance
        uint256 beforeBal = IERC20(WBERA).balanceOf(user);
        vm.prank(address(brc20));
        rewarder.onWithdraw(user, 100e18); // Withdraw some shares
        uint256 afterBal = IERC20(WBERA).balanceOf(user);

        // Should receive all available balance (1e18)
        assertEq(afterBal - beforeBal, 1e18);

        // Position should be closed due to underfunding
        (uint256 pendingAfter, uint256 trackedSharesAfter, ) = rewarder
            .viewPending(user);
        assertEq(pendingAfter, 0);
        assertEq(trackedSharesAfter, 0);
    }

    function testFRewarder2ClaimUnderfunding() public forkOnly {
        // Deploy BRC20 and Rewarder2
        BRC20 brc20 = new BRC20(
            "Burve BRC20",
            "bBRC20",
            OMNIPOOL,
            3,
            address(0),
            0
        );
        Rewarder2 rewarder = new Rewarder2(address(brc20), WBERA, 1 << 64); // 1 token/hour/share

        // Wire rewarder into BRC20
        brc20.setRewarder(address(rewarder));

        // Fund with small amount
        deal(WBERA, address(this), 2e18);
        IERC20(WBERA).approve(address(rewarder), type(uint256).max);
        rewarder.fund(2e18);

        address user = address(this);

        // Deposit shares
        vm.prank(address(brc20));
        rewarder.onDeposit(user, 1000e18);

        // Wait to accrue more than available
        vm.warp(block.timestamp + 3600); // 1 hour

        // First claim should get all available balance
        uint256 beforeBal1 = IERC20(WBERA).balanceOf(user);
        rewarder.claim();
        uint256 afterBal1 = IERC20(WBERA).balanceOf(user);
        assertEq(afterBal1 - beforeBal1, 2e18);

        // Position should be closed
        (uint256 pending, , ) = rewarder.viewPending(user);
        assertEq(pending, 0);

        // Second claim should not revert and pay nothing
        uint256 beforeBal2 = IERC20(WBERA).balanceOf(user);
        rewarder.claim();
        uint256 afterBal2 = IERC20(WBERA).balanceOf(user);
        assertEq(afterBal2 - beforeBal2, 0);
    }

    function testFRewarder2PartialUnderfunding() public forkOnly {
        // Deploy BRC20 and Rewarder2
        BRC20 brc20 = new BRC20(
            "Burve BRC20",
            "bBRC20",
            OMNIPOOL,
            3,
            address(0),
            0
        );
        Rewarder2 rewarder = new Rewarder2(address(brc20), WBERA, 1 << 64); // 1 token/hour/share

        // Wire rewarder into BRC20
        brc20.setRewarder(address(rewarder));

        // Fund with moderate amount
        deal(WBERA, address(this), 500e18);
        IERC20(WBERA).approve(address(rewarder), type(uint256).max);
        rewarder.fund(500e18);

        address user = address(this);

        // Deposit shares
        vm.prank(address(brc20));
        rewarder.onDeposit(user, 1000e18);

        // Wait to accrue more than available
        vm.warp(block.timestamp + 3600); // 1 hour

        // Check what's owed vs available
        (uint256 pending, , ) = rewarder.viewPending(user);
        uint256 available = IERC20(WBERA).balanceOf(address(rewarder));
        console2.log("Pending rewards:", pending);
        console2.log("Available balance:", available);

        // Should pay out all available balance and close position
        uint256 beforeBal = IERC20(WBERA).balanceOf(user);
        vm.prank(address(brc20));
        rewarder.onWithdraw(user, 100e18);
        uint256 afterBal = IERC20(WBERA).balanceOf(user);

        // Should receive all available balance
        assertEq(afterBal - beforeBal, available);

        // Position should be closed
        (uint256 pendingAfter, , ) = rewarder.viewPending(user);
        assertEq(pendingAfter, 0);
    }

    function testFRewarder2AccumulationPause() public forkOnly {
        // Deploy BRC20 and Rewarder2
        BRC20 brc20 = new BRC20(
            "Burve BRC20",
            "bBRC20",
            OMNIPOOL,
            3,
            address(0),
            0
        );
        Rewarder2 rewarder = new Rewarder2(address(brc20), WBERA, 1 << 64); // 1 token/hour/share

        // Wire rewarder into BRC20
        brc20.setRewarder(address(rewarder));

        // Fund with small amount
        deal(WBERA, address(this), 1e18);
        IERC20(WBERA).approve(address(rewarder), type(uint256).max);
        rewarder.fund(1e18);

        address user1 = address(0x1);
        address user2 = address(0x2);

        // User 1 deposits large amount
        vm.prank(address(brc20));
        rewarder.onDeposit(user1, 100e18);

        // User 2 deposits large amount
        vm.prank(address(brc20));
        rewarder.onDeposit(user2, 100e18);

        // Wait to accrue rewards
        vm.warp(block.timestamp + 7 days);

        // Check total unclaimed rewards
        uint256 totalUnclaimed = rewarder.calculateTotalUnclaimedRewards();
        uint256 availableBalance = IERC20(WBERA).balanceOf(address(rewarder));
        console2.log("Total unclaimed:", totalUnclaimed);
        console2.log("Available balance:", availableBalance);
        console2.log("Should pause:", rewarder.shouldPauseAccumulation());

        // // User 1 deposits large amount
        // vm.prank(address(brc20));
        // rewarder.onDeposit(user1, 100e18);

        // // User 2 deposits large amount
        // vm.prank(address(brc20));
        // rewarder.onDeposit(user2, 100e18);

        // If unclaimed > available, accumulation should be paused
        if (totalUnclaimed >= availableBalance) {
            // assertTrue(rewarder.accumulationPaused());

            // Check that pending rewards are 0 when paused
            (uint256 pending1, , ) = rewarder.viewPending(user1);
            (uint256 pending2, , ) = rewarder.viewPending(user2);
            assertGt(pending1, 0);
            assertGt(pending2, 0);
        }

        // Test that users can still claim their existing rewards
        uint256 beforeBal1 = IERC20(WBERA).balanceOf(user1);
        vm.prank(address(brc20));
        rewarder.onWithdraw(user1, 100e18);
        uint256 afterBal1 = IERC20(WBERA).balanceOf(user1);

        // Should receive some rewards (up to available balance)
        assertTrue(afterBal1 > beforeBal1);
    }

    function testFRewarder2ResumeAccumulation() public forkOnly {
        // Deploy BRC20 and Rewarder2
        BRC20 brc20 = new BRC20(
            "Burve BRC20",
            "bBRC20",
            OMNIPOOL,
            3,
            address(0),
            0
        );
        Rewarder2 rewarder = new Rewarder2(address(brc20), WBERA, 1 << 64); // 1 token/hour/share

        // Wire rewarder into BRC20
        brc20.setRewarder(address(rewarder));

        // Fund with small amount to trigger pause
        deal(WBERA, address(this), 1e18);
        IERC20(WBERA).approve(address(rewarder), type(uint256).max);
        rewarder.fund(1e18);

        address user = address(this);

        // Deposit and wait to trigger pause
        vm.prank(address(brc20));
        rewarder.onDeposit(user, 1000e18);
        vm.warp(block.timestamp + 3600); // 1 hour

        vm.prank(address(brc20));
        rewarder.onDeposit(user, 1e18);

        // Should be paused
        assertTrue(rewarder.accumulationPaused());

        // Add more funds
        deal(WBERA, address(this), 1000e18);
        rewarder.fund(1000e18);

        // Resume accumulation
        rewarder.resumeAccumulation();
        assertFalse(rewarder.accumulationPaused());

        // Wait and check that rewards are accumulating again
        // vm.warp(block.timestamp + 3600); // 1 more hour
        // (uint256 pending, , ) = rewarder.viewPending(user);
        // assertTrue(pending > 0);
    }

    function testFRewarder2PendingMatchesCollection() public forkOnly {
        // Deploy BRC20 and Rewarder2
        BRC20 brc20 = new BRC20(
            "Burve BRC20",
            "bBRC20",
            OMNIPOOL,
            3,
            address(0),
            0
        );
        Rewarder2 rewarder = new Rewarder2(address(brc20), WBERA, 1 << 64); // 1 token/hour/share

        // Wire rewarder into BRC20
        brc20.setRewarder(address(rewarder));

        // Fund rewarder with sufficient amount
        deal(WBERA, address(this), 1000e18);
        IERC20(WBERA).approve(address(rewarder), type(uint256).max);
        rewarder.fund(1000e18);

        address user = address(this);

        // Deposit shares
        vm.prank(address(brc20));
        rewarder.onDeposit(user, 1e18);

        // Let time pass without collecting rewards
        vm.warp(block.timestamp + 3600); // 1 hour

        // Check pending rewards - should simulate collection up to current time
        (
            uint256 pendingBefore,
            uint256 trackedShares,
            uint256 lastTimestamp
        ) = rewarder.viewPending(user);

        // Expected: 1e18 shares * 1 token/hour/share * 1 hour = 1e18 tokens
        uint256 expectedRewards = 1e18;
        assertApproxEqAbs(pendingBefore, expectedRewards, 1e6); // Allow small precision error
        assertEq(trackedShares, 1e18);
        assertGt(lastTimestamp, 0);

        // Now actually collect the rewards
        uint256 balanceBefore = IERC20(WBERA).balanceOf(user);
        rewarder.claim();
        uint256 balanceAfter = IERC20(WBERA).balanceOf(user);
        uint256 actualCollected = balanceAfter - balanceBefore;

        // The collected amount should match the pending amount we calculated
        assertApproxEqAbs(actualCollected, pendingBefore, 1e6);

        // After collection, pending should be 0
        (uint256 pendingAfter, , ) = rewarder.viewPending(user);
        assertEq(pendingAfter, 0);

        // Test with partial time accumulation
        vm.warp(block.timestamp + 1800); // 30 minutes

        // Check pending rewards for 30 minutes
        (uint256 pendingPartial, , ) = rewarder.viewPending(user);

        // Expected: 1e18 shares * 1 token/hour/share * 0.5 hour = 0.5e18 tokens
        uint256 expectedPartialRewards = 5e17; // 0.5e18
        assertApproxEqAbs(pendingPartial, expectedPartialRewards, 1e6);

        // Collect and verify
        balanceBefore = IERC20(WBERA).balanceOf(user);
        rewarder.claim();
        balanceAfter = IERC20(WBERA).balanceOf(user);
        actualCollected = balanceAfter - balanceBefore;

        assertApproxEqAbs(actualCollected, pendingPartial, 1e6);

        // // Test with multiple users to ensure individual tracking
        // address user2 = address(0x1234);

        // // User2 deposits shares
        // vm.prank(address(brc20));
        // rewarder.onDeposit(user2, 2e18); // 2x shares

        // vm.warp(block.timestamp + 3600); // 1 hour

        // // Check both users' pending rewards
        // (uint256 pendingUser1, , ) = rewarder.viewPending(user);
        // (uint256 pendingUser2, , ) = rewarder.viewPending(user2);

        // // User1: 1e18 shares * 1 token/hour/share * 1 hour = 1e18
        // // User2: 2e18 shares * 1 token/hour/share * 1 hour = 2e18
        // assertApproxEqAbs(pendingUser1, 1e18, 1e6);
        // assertApproxEqAbs(pendingUser2, 2e18, 1e6);

        // // Collect for both users and verify
        // balanceBefore = IERC20(WBERA).balanceOf(user);
        // rewarder.claim();
        // balanceAfter = IERC20(WBERA).balanceOf(user);
        // actualCollected = balanceAfter - balanceBefore;
        // assertApproxEqAbs(actualCollected, pendingUser1, 1e6);

        // balanceBefore = IERC20(WBERA).balanceOf(user2);
        // vm.prank(user2);
        // rewarder.claim();
        // balanceAfter = IERC20(WBERA).balanceOf(user2);
        // actualCollected = balanceAfter - balanceBefore;
        // assertApproxEqAbs(actualCollected, pendingUser2, 1e6);
    }
}
