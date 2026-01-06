// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BeraAirdrop} from "../src/BeraAirdrop.sol";

contract BeraAirdropTest is Test {
    BeraAirdrop public airdrop;
    address public owner;
    address public user;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");

        vm.prank(owner);
        airdrop = new BeraAirdrop();

        // Fund the contract with 100,000 BERA
        vm.deal(address(airdrop), 100_000 ether);
    }

    function testConstructor() public view {
        assertEq(airdrop.owner(), owner);
        assertEq(airdrop.recipientCount(), 44);
        assertEq(airdrop.distributed(), false);
    }

    function testDistributeAll() public {
        vm.prank(owner);
        airdrop.distributeAll();

        assertEq(airdrop.distributed(), true);

        // Verify first recipient received correct amount
        (address firstAddr, ) = airdrop.recipients(0);
        assertEq(firstAddr, 0x6eA0cd91291BaF975Ec0E5Ec5b5803455360150b);
        assertGt(firstAddr.balance, 0);
    }

    function testDistributeBatch() public {
        vm.prank(owner);
        airdrop.distributeBatch(0, 10);

        // Verify first recipient received funds
        (address firstAddr, ) = airdrop.recipients(0);
        assertGt(firstAddr.balance, 0);

        // Verify 11th recipient hasn't received funds yet
        (address eleventhAddr, ) = airdrop.recipients(10);
        assertEq(eleventhAddr.balance, 0);
    }

    function testDistributeSingle() public {
        vm.prank(owner);
        airdrop.distributeSingle(0);

        (address addr, uint256 amount) = airdrop.recipients(0);
        assertEq(addr.balance, amount);
    }

    function testCannotDistributeTwice() public {
        vm.prank(owner);
        airdrop.distributeAll();

        vm.prank(owner);
        vm.expectRevert(BeraAirdrop.AlreadyDistributed.selector);
        airdrop.distributeAll();
    }

    function testOnlyOwnerCanDistribute() public {
        vm.prank(user);
        vm.expectRevert(BeraAirdrop.OnlyOwner.selector);
        airdrop.distributeAll();
    }

    function testInsufficientBalance() public {
        // Deploy new airdrop without funding
        vm.prank(owner);
        BeraAirdrop unfundedAirdrop = new BeraAirdrop();

        vm.prank(owner);
        vm.expectRevert(BeraAirdrop.InsufficientBalance.selector);
        unfundedAirdrop.distributeAll();
    }

    function testWithdraw() public {
        uint256 balanceBefore = owner.balance;

        vm.prank(owner);
        airdrop.withdraw();

        assertEq(owner.balance, balanceBefore + 100_000 ether);
        assertEq(address(airdrop).balance, 0);
    }

    function testVerifyTotalDistribution() public view {
        uint256 totalCalculated = 0;

        for (uint256 i = 0; i < airdrop.recipientCount(); i++) {
            (, uint256 amount) = airdrop.recipients(i);
            totalCalculated += amount;
        }

        // Should be very close to 100,000 BERA (within rounding tolerance)
        assertApproxEqRel(totalCalculated, 100_000 ether, 0.01e18); // 1% tolerance
    }

    function testRecipientAmounts() public view {
        // Test first recipient (highest points)
        (address addr0, uint256 amount0) = airdrop.recipients(0);
        assertEq(addr0, 0x6eA0cd91291BaF975Ec0E5Ec5b5803455360150b);
        assertEq(amount0, 29871465802580801791954);

        // Test second recipient
        (address addr1, uint256 amount1) = airdrop.recipients(1);
        assertEq(addr1, 0xc137942872586E5847d66025c9aE04b89053Cb58);
        assertEq(amount1, 25078234126687136107136);
    }
}
