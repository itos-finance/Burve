// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "Commons/Math/Cast.sol";
import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {ForkableTest} from "Commons/Test/ForkableTest.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {DiamondCutFacet} from "Commons/Diamond/facets/DiamondCutFacet.sol";
import {RFTPayer} from "Commons/Util/RFT.sol";
import {Auto165} from "Commons/ERC/Auto165.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";

import {BRC20} from "../../src/integrations/BRC20.sol";
import {Rewarder2} from "../../src/integrations/Rewarder2.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {IBurveMultiValue} from "../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {IBurveMultiSwap} from "../../src/multi/interfaces/IBurveMultiSwap.sol";

contract Rewarder2BRC20Test is ForkableTest, RFTPayer, Auto165 {
    // Live Burve pool address on Berachain
    address public constant BURVE_POOL =
        0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;

    // Closure ID to test with
    uint16 public constant CLOSURE_ID = 3;

    // Token addresses from usd.json
    address public constant USDC = 0x549943e04f40284185054145c6E4e9568C1D3241;
    address public constant USDT = 0x779Ded0c9e1022225f8E0630b35a9b54bE713736;

    // BRC20 and Rewarder2 contract instances
    BRC20 public brc20;
    Rewarder2 public rewarder;
    MockERC20 public rewardToken;

    // Pool interfaces
    IBurveMultiValue public pool;
    IBurveMultiSimplex public simplex;

    // Token instances
    IERC20 public usdc;
    IERC20 public usdt;

    // Test users
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    // Reward rate: 1 token per hour per share (in X64 fixed point)
    uint256 public constant REWARD_RATE_X64 = 1e18 << 64; // 1e18 * 2^64

    function preSetup() internal override {}

    function deploySetup() internal override {
        // This will run when not forking (local testing)
        _deployLocalSetup();
    }

    function forkSetup() internal override {
        // This will run when forking from Berachain
        _setupFork();
    }

    function _deployLocalSetup() internal {
        // Mock setup for local testing
        // Deploy mock reward token
        rewardToken = new MockERC20("Test Reward Token", "TRT", 18);

        // Deploy BRC20 contract
        brc20 = new BRC20(
            "Test BRC20",
            "tBRC20",
            address(this), // Mock pool for local testing
            CLOSURE_ID,
            address(0), // no PoL vault
            0 // no fee take
        );

        // Deploy Rewarder2 contract
        rewarder = new Rewarder2(
            address(brc20),
            address(rewardToken),
            REWARD_RATE_X64
        );

        // Set rewarder in BRC20
        brc20.setRewarder(address(rewarder));
    }

    function _setupFork() internal {
        // Set up the fork environment
        pool = IBurveMultiValue(BURVE_POOL);
        simplex = IBurveMultiSimplex(BURVE_POOL);

        // Initialize token instances
        usdc = IERC20(USDC);
        usdt = IERC20(USDT);

        // Deploy mock reward token
        rewardToken = new MockERC20("Test Reward Token", "TRT", 18);

        // Deploy BRC20 contract
        brc20 = new BRC20(
            "Test BRC20",
            "tBRC20",
            BURVE_POOL,
            CLOSURE_ID,
            address(0), // no PoL vault
            0 // no fee take
        );

        // Deploy Rewarder2 contract
        rewarder = new Rewarder2(
            address(brc20),
            address(rewardToken),
            REWARD_RATE_X64
        );

        // Set rewarder in BRC20
        brc20.setRewarder(address(rewarder));

        console2.log("BRC20 deployed at:", address(brc20));
        console2.log("Rewarder2 deployed at:", address(rewarder));
        console2.log("Reward token deployed at:", address(rewardToken));

        _cutValueFacet(BURVE_POOL);
    }

    function _cutValueFacet(address diamond) public {
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ValueFacet.collectEarnings.selector;

        cuts[0] = (
            IDiamond.FacetCut({
                facetAddress: address(new ValueFacet()),
                action: IDiamond.FacetCutAction.Replace,
                functionSelectors: selectors
            })
        );

        DiamondCutFacet cutFacet = DiamondCutFacet(diamond);

        // prank as the multisig
        vm.startPrank(address(0x9293f9FFC43F6fce06290285919541E963D87F51));
        BaseAdminFacet(BURVE_POOL).acceptOwnership();
        cutFacet.diamondCut(cuts, address(0), "");
        vm.stopPrank();
    }

    function testRewarder2Initialization() public view {
        assertEq(rewarder.brc20(), address(brc20));
        assertEq(address(rewarder.rewardToken()), address(rewardToken));
        assertEq(rewarder.tokensPerHourPerShareX64(), REWARD_RATE_X64);
        assertEq(brc20.rewarder(), address(rewarder));
    }

    function testDepositTracking() public forkOnly {
        uint128 depositValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Fund the rewarder with some tokens
        rewardToken.mint(address(this), 1000e18);
        rewardToken.approve(address(rewarder), 1000e18);
        rewarder.fund(1000e18);

        // Check initial state
        (
            uint256 pending,
            uint256 trackedShares,
            uint256 lastTimestamp
        ) = rewarder.viewPending(user1);
        assertEq(pending, 0);
        assertEq(trackedShares, 0);
        assertEq(lastTimestamp, 0);

        // User1 deposits
        vm.prank(user1);
        brc20.addValue(user1, 0, depositValue, 0, amountLimits);

        uint256 user1Shares = brc20.balanceOf(user1);
        assertGt(user1Shares, 0);

        // Check that rewarder tracked the deposit
        (pending, trackedShares, lastTimestamp) = rewarder.viewPending(user1);
        assertEq(trackedShares, user1Shares);
        assertEq(pending, 0); // No time elapsed yet
        assertGt(lastTimestamp, 0);

        console2.log("User1 shares:", user1Shares);
        console2.log("Tracked shares in rewarder:", trackedShares);
        console2.log("Last timestamp:", lastTimestamp);
    }

    function testWithdrawalTracking() public forkOnly {
        uint128 depositValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Fund the rewarder
        rewardToken.mint(address(this), 1000e18);
        rewardToken.approve(address(rewarder), 1000e18);
        rewarder.fund(1000e18);

        // User1 deposits
        vm.prank(user1);
        brc20.addValue(user1, 0, depositValue, 0, amountLimits);

        uint256 user1Shares = brc20.balanceOf(user1);

        // Check tracked shares before withdrawal
        (
            uint256 pending,
            uint256 trackedShares,
            uint256 lastTimestamp
        ) = rewarder.viewPending(user1);
        assertEq(trackedShares, user1Shares);

        // User1 withdraws half their shares
        uint128 withdrawShares = uint128(user1Shares / 2);
        vm.prank(user1);
        brc20.removeValue(user1, 0, withdrawShares, 0, amountLimits);

        // Check that rewarder tracked the withdrawal
        (pending, trackedShares, lastTimestamp) = rewarder.viewPending(user1);
        assertEq(trackedShares, user1Shares - withdrawShares);
        assertEq(brc20.balanceOf(user1), user1Shares - withdrawShares);

        console2.log("User1 remaining shares:", user1Shares - withdrawShares);
        console2.log("Tracked shares in rewarder:", trackedShares);
    }

    function testRewardAccumulation() public forkOnly {
        uint128 depositValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Fund the rewarder
        rewardToken.mint(address(this), 1000e18);
        rewardToken.approve(address(rewarder), 1000e18);
        rewarder.fund(1000e18);

        // User1 deposits
        vm.prank(user1);
        brc20.addValue(user1, 0, depositValue, 0, amountLimits);

        uint256 user1Shares = brc20.balanceOf(user1);

        // Fast forward 1 hour (3600 seconds)
        vm.warp(block.timestamp + 3600);

        // Check pending rewards
        (
            uint256 pending,
            uint256 trackedShares,
            uint256 lastTimestamp
        ) = rewarder.viewPending(user1);
        assertEq(trackedShares, user1Shares);

        // Calculate expected rewards: shares * rate * time
        // rate = 1e18 tokens per hour per share
        // time = 1 hour = 3600 seconds
        uint256 expectedRewards = user1Shares; // 1 token per hour per share

        console2.log("Expected rewards:", expectedRewards);
        console2.log("Pending rewards:", pending);
        console2.log("User1 shares:", user1Shares);

        // Allow some tolerance for precision
        assertApproxEqRel(pending, expectedRewards, 0.01e18); // 1% tolerance
    }

    function testRewardClaiming() public forkOnly {
        uint128 depositValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Fund the rewarder
        rewardToken.mint(address(this), 1000e18);
        rewardToken.approve(address(rewarder), 1000e18);
        rewarder.fund(1000e18);

        // User1 deposits
        vm.prank(user1);
        brc20.addValue(user1, 0, depositValue, 0, amountLimits);

        uint256 user1Shares = brc20.balanceOf(user1);

        // Fast forward 1 hour
        vm.warp(block.timestamp + 3600);

        // Check pending rewards
        (uint256 pending, , ) = rewarder.viewPending(user1);
        assertGt(pending, 0);

        // User1 claims rewards
        uint256 initialBalance = rewardToken.balanceOf(user1);
        vm.prank(user1);
        rewarder.claim();

        uint256 finalBalance = rewardToken.balanceOf(user1);
        uint256 claimed = finalBalance - initialBalance;

        console2.log("Initial balance:", initialBalance);
        console2.log("Final balance:", finalBalance);
        console2.log("Claimed rewards:", claimed);
        console2.log("Pending before claim:", pending);

        assertApproxEqRel(claimed, pending, 0.01e18); // 1% tolerance

        // Check that pending is now 0
        (pending, , ) = rewarder.viewPending(user1);
        assertEq(pending, 0);
    }

    function testMultipleUsers() public forkOnly {
        uint128 depositValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Fund the rewarder
        rewardToken.mint(address(this), 1000e18);
        rewardToken.approve(address(rewarder), 1000e18);
        rewarder.fund(1000e18);

        // User1 deposits
        vm.prank(user1);
        brc20.addValue(user1, 0, depositValue, 0, amountLimits);

        // User2 deposits
        vm.prank(user2);
        brc20.addValue(user2, 0, depositValue, 0, amountLimits);

        // User3 deposits
        vm.prank(user3);
        brc20.addValue(user3, 0, depositValue, 0, amountLimits);

        uint256 user1Shares = brc20.balanceOf(user1);
        uint256 user2Shares = brc20.balanceOf(user2);
        uint256 user3Shares = brc20.balanceOf(user3);

        // Fast forward 1 hour
        vm.warp(block.timestamp + 3600);

        // Check that all users have pending rewards
        (uint256 pending1, , ) = rewarder.viewPending(user1);
        (uint256 pending2, , ) = rewarder.viewPending(user2);
        (uint256 pending3, , ) = rewarder.viewPending(user3);

        assertGt(pending1, 0);
        assertGt(pending2, 0);
        assertGt(pending3, 0);

        // All users should have similar rewards (proportional to their shares)
        assertApproxEqRel(pending1, user1Shares, 0.01e18);
        assertApproxEqRel(pending2, user2Shares, 0.01e18);
        assertApproxEqRel(pending3, user3Shares, 0.01e18);

        console2.log("User1 pending:", pending1);
        console2.log("User2 pending:", pending2);
        console2.log("User3 pending:", pending3);
    }

    function testPartialWithdrawal() public forkOnly {
        uint128 depositValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Fund the rewarder
        rewardToken.mint(address(this), 1000e18);
        rewardToken.approve(address(rewarder), 1000e18);
        rewarder.fund(1000e18);

        // User1 deposits
        vm.prank(user1);
        brc20.addValue(user1, 0, depositValue, 0, amountLimits);

        uint256 user1Shares = brc20.balanceOf(user1);

        // Fast forward 30 minutes
        vm.warp(block.timestamp + 1800);

        // Check pending rewards
        (uint256 pendingBefore, , ) = rewarder.viewPending(user1);
        assertGt(pendingBefore, 0);

        // User1 withdraws half their shares
        uint128 withdrawShares = uint128(user1Shares / 2);
        vm.prank(user1);
        brc20.removeValue(user1, 0, withdrawShares, 0, amountLimits);

        // Check that rewards were settled and tracked shares updated
        (uint256 pendingAfter, uint256 trackedShares, ) = rewarder.viewPending(
            user1
        );
        assertEq(trackedShares, user1Shares - withdrawShares);

        // User should have received some rewards from the settlement
        uint256 user1Balance = rewardToken.balanceOf(user1);
        assertGt(user1Balance, 0);

        console2.log("Pending before withdrawal:", pendingBefore);
        console2.log("Pending after withdrawal:", pendingAfter);
        console2.log("User1 reward balance:", user1Balance);
        console2.log("Remaining tracked shares:", trackedShares);
    }

    function testUnderfundedRewards() public forkOnly {
        uint128 depositValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Fund the rewarder with only a small amount
        rewardToken.mint(address(this), 1e18); // Only 1 token
        rewardToken.approve(address(rewarder), 1e18);
        rewarder.fund(1e18);

        // User1 deposits
        vm.prank(user1);
        brc20.addValue(user1, 0, depositValue, 0, amountLimits);

        uint256 user1Shares = brc20.balanceOf(user1);

        // Fast forward 2 hours (more than the funded amount)
        vm.warp(block.timestamp + 7200);

        // Check pending rewards
        (uint256 pending, , ) = rewarder.viewPending(user1);
        assertGt(pending, 0);

        // User1 claims rewards - should only get what's available
        uint256 initialBalance = rewardToken.balanceOf(user1);
        vm.prank(user1);
        rewarder.claim();

        uint256 finalBalance = rewardToken.balanceOf(user1);
        uint256 claimed = finalBalance - initialBalance;

        // Should only get the funded amount (1 token)
        assertEq(claimed, 1e18);

        // Check that the position was closed due to underfunding
        (
            uint256 pendingAfter,
            uint256 trackedShares,
            uint256 lastTimestamp
        ) = rewarder.viewPending(user1);
        assertEq(trackedShares, 0);
        assertEq(lastTimestamp, 0);
        assertEq(pendingAfter, 0);

        console2.log("Claimed rewards (underfunded):", claimed);
        console2.log("Tracked shares after claim:", trackedShares);
    }

    function testRateUpdate() public {
        uint256 newRate = 2e18 << 64; // 2 tokens per hour per share

        // Update the rate
        rewarder.setRatePerHourPerShareX64(newRate);

        assertEq(rewarder.tokensPerHourPerShareX64(), newRate);
    }

    function testAdminFunctions() public {
        // Test funding
        rewardToken.mint(address(this), 1000e18);
        rewardToken.approve(address(rewarder), 1000e18);

        uint256 initialBalance = rewardToken.balanceOf(address(rewarder));
        rewarder.fund(500e18);
        uint256 finalBalance = rewardToken.balanceOf(address(rewarder));

        assertEq(finalBalance - initialBalance, 500e18);

        // Test withdrawal
        uint256 withdrawAmount = 100e18;
        uint256 initialUserBalance = rewardToken.balanceOf(user1);
        rewarder.withdraw(withdrawAmount, user1);
        uint256 finalUserBalance = rewardToken.balanceOf(user1);

        assertEq(finalUserBalance - initialUserBalance, withdrawAmount);
    }

    function testOnlyBRC20Modifier() public {
        // Try to call onDeposit from non-BRC20 address - should revert
        vm.expectRevert("Only BRC20");
        rewarder.onDeposit(user1, 1000);

        // Try to call onWithdraw from non-BRC20 address - should revert
        vm.expectRevert("Only BRC20");
        rewarder.onWithdraw(user1, 1000);
    }

    function testRewardCalculationPrecision() public forkOnly {
        uint128 depositValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Fund the rewarder
        rewardToken.mint(address(this), 1000e18);
        rewardToken.approve(address(rewarder), 1000e18);
        rewarder.fund(1000e18);

        // User1 deposits
        vm.prank(user1);
        brc20.addValue(user1, 0, depositValue, 0, amountLimits);

        uint256 user1Shares = brc20.balanceOf(user1);

        // Fast forward exactly 1 second
        vm.warp(block.timestamp + 1);

        // Check pending rewards for 1 second
        (uint256 pending, , ) = rewarder.viewPending(user1);

        // Expected: shares * rate * time / 3600
        // rate = 1e18 tokens per hour = 1e18/3600 tokens per second
        // time = 1 second
        uint256 expectedPerSecond = (user1Shares * REWARD_RATE_X64) >> 64;
        expectedPerSecond = expectedPerSecond / 3600;

        console2.log("Expected per second:", expectedPerSecond);
        console2.log("Actual pending:", pending);
        console2.log("User1 shares:", user1Shares);

        // Should be very close to expected
        assertApproxEqRel(pending, expectedPerSecond, 0.01e18);
    }

    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata
    ) external returns (bytes memory) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (requests[i] > 0) {
                deal(tokens[i], address(this), SafeCast.toUint256(requests[i]));
                // minting
                TransferHelper.safeTransfer(
                    tokens[i],
                    msg.sender,
                    SafeCast.toUint256(requests[i])
                );
            }
        }

        return "";
    }

    function testFRewarder2BRC20PendingMatchesCollection() public forkOnly {
        // Deploy BRC20 and Rewarder2
        BRC20 testBRC20 = new BRC20(
            "Burve BRC20",
            "bBRC20",
            BURVE_POOL,
            3,
            address(0),
            0
        );
        MockERC20 testRewardToken = new MockERC20(
            "Test Reward Token",
            "TRT",
            18
        );
        Rewarder2 testRewarder = new Rewarder2(
            address(testBRC20),
            address(testRewardToken),
            1 << 64
        ); // 1 token/hour/share

        // Wire rewarder into BRC20
        testBRC20.setRewarder(address(testRewarder));

        // Fund rewarder
        testRewardToken.mint(address(this), 1000e18);
        testRewardToken.approve(address(testRewarder), 1000e18);
        testRewarder.fund(1000e18);

        address testUser1 = address(this);

        // Approve BRC20 contract to spend our tokens
        // We need to approve the tokens that will be used for the deposit
        address[] memory tokens = testBRC20.getTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).approve(address(testBRC20), type(uint256).max);
        }

        // Deposit via BRC20 (which calls rewarder hooks)
        uint128 depositValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        testBRC20.addValue(testUser1, 0, depositValue, 0, amountLimits);

        uint256 testUser1Shares = testBRC20.balanceOf(testUser1);
        assertGt(testUser1Shares, 0);

        // Let time pass without collecting rewards
        vm.warp(block.timestamp + 3600); // 1 hour

        // Check pending rewards - should simulate collection up to current time
        (
            uint256 pendingBefore,
            uint256 trackedShares,
            uint256 lastTimestamp
        ) = testRewarder.viewPending(testUser1);

        // Expected: testUser1Shares * 1 token/hour/share * 1 hour
        uint256 expectedRewards = testUser1Shares; // 1 token per hour per share
        assertApproxEqAbs(pendingBefore, expectedRewards, 1e6); // Allow small precision error
        assertEq(trackedShares, testUser1Shares);
        assertGt(lastTimestamp, 0);

        // Now actually collect the rewards via direct claim
        uint256 balanceBefore = testRewardToken.balanceOf(testUser1);
        testRewarder.claim();
        uint256 balanceAfter = testRewardToken.balanceOf(testUser1);
        uint256 actualCollected = balanceAfter - balanceBefore;

        // The collected amount should match the pending amount we calculated
        assertApproxEqAbs(actualCollected, pendingBefore, 1e6);

        // After collection, pending should be 0
        (uint256 pendingAfter, , ) = testRewarder.viewPending(testUser1);
        assertEq(pendingAfter, 0);

        // Test with partial time accumulation
        vm.warp(block.timestamp + 1800); // 30 minutes

        // Check pending rewards for 30 minutes
        (uint256 pendingPartial, , ) = testRewarder.viewPending(testUser1);

        // Expected: testUser1Shares * 1 token/hour/share * 0.5 hour
        uint256 expectedPartialRewards = testUser1Shares / 2; // 0.5 hour
        assertApproxEqAbs(pendingPartial, expectedPartialRewards, 1e6);

        // Collect and verify
        uint256 balanceBefore2 = testRewardToken.balanceOf(testUser1);
        testRewarder.claim();
        uint256 balanceAfter2 = testRewardToken.balanceOf(testUser1);
        uint256 actualCollected2 = balanceAfter2 - balanceBefore2;

        assertApproxEqAbs(actualCollected2, pendingPartial, 1e6);

        // Test that BRC20 withdrawal also respects pending calculation
        vm.warp(block.timestamp + 3600); // 1 more hour

        // Check pending before withdrawal
        (uint256 pendingBeforeWithdraw, , ) = testRewarder.viewPending(
            testUser1
        );
        assertGt(pendingBeforeWithdraw, 0);

        // Withdraw half the shares via BRC20
        uint128 withdrawShares = uint128(testUser1Shares / 2);
        testBRC20.removeValue(testUser1, 0, withdrawShares, 0, amountLimits);

        // Check that rewards were settled and pending is now 0
        (
            uint256 pendingAfterWithdraw,
            uint256 trackedSharesAfter,

        ) = testRewarder.viewPending(testUser1);
        assertEq(trackedSharesAfter, testUser1Shares - uint256(withdrawShares));
        assertEq(pendingAfterWithdraw, 0); // Should be 0 after withdrawal settlement
    }
}
