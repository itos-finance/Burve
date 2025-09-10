// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {BurveForkableTest} from "../../test/integrations/Fork.u.sol";
import {Rewarder2} from "../../src/integrations/Rewarder2.sol";
import {BRC20} from "../../src/integrations/BRC20.sol";

contract FRewarder2 is BurveForkableTest {
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
        uint256 afterBal = IERC20(WBERA).balanceOf(user);

        // Expect ~1e18 tokens (1 token/hour/share * 1e18 shares * 1 hour)
        assertApproxEqAbs(afterBal - beforeBal, 1e18, 1);
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
}
