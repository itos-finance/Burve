// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockERC4626} from "../../mocks/MockERC4626.sol";
import {FeeVaultWrapper} from "../../../src/integrations/fee4626/FeeVaultWrapper.sol";
import {MultiSetupTest} from "../../facets/MultiSetup.u.sol";
import {VaultType} from "../../../src/multi/vertex/VaultProxy.sol";

contract FeeVaultWrapperTest is MultiSetupTest {
    FeeVaultWrapper public feeVault;
    MockERC4626 public underlyingVault;
    MockERC20 public asset;
    address public feeRecipient;

    uint256 constant DEPOSIT_AMOUNT = 1000e18;
    uint16 constant ONE_PERCENT = 100; // 1% in basis points
    uint16 constant TEN_PERCENT = 1000; // 10% max fee

    function setUp() public {
        // Create test accounts
        feeRecipient = makeAddr("feeRecipient");

        // Deploy asset (18 decimals)
        asset = new MockERC20("Test USD", "USDT", 18);
        asset.mint(alice, 100_000e18);
        asset.mint(bob, 100_000e18);

        // Deploy underlying vault (simulates Aave aToken)
        underlyingVault = new MockERC4626(asset, "Mock Vault", "mVault");

        // Deploy fee wrapper with 0% initial fees
        feeVault = new FeeVaultWrapper(
            IERC4626(address(underlyingVault)),
            "Fee Vault Wrapper",
            "fVault",
            feeRecipient
        );
    }

    // ============ Phase 1: No-Fee Tests ============

    function testNoFeeDeposit() public {
        vm.startPrank(alice);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);

        uint256 shares = feeVault.deposit(DEPOSIT_AMOUNT, alice);

        // With 0% fee, should get full shares
        assertEq(feeVault.balanceOf(alice), shares, "Alice should receive shares");
        assertEq(feeVault.totalAssets(), DEPOSIT_AMOUNT, "Total assets should match deposit");
        assertEq(asset.balanceOf(feeRecipient), 0, "No fees should be collected");

        vm.stopPrank();
    }

    function testNoFeeWithdraw() public {
        // First deposit
        vm.startPrank(alice);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);
        uint256 shares = feeVault.deposit(DEPOSIT_AMOUNT, alice);

        // Then withdraw
        uint256 assetsReceived = feeVault.redeem(shares, alice, alice);

        assertEq(assetsReceived, DEPOSIT_AMOUNT, "Should receive full amount back");
        assertEq(feeVault.balanceOf(alice), 0, "All shares should be burned");
        assertEq(asset.balanceOf(feeRecipient), 0, "No fees should be collected");

        vm.stopPrank();
    }

    function testNoFeeShareCalculation() public {
        // Alice deposits
        vm.startPrank(alice);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);
        uint256 aliceShares = feeVault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        // Bob deposits same amount
        vm.startPrank(bob);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);
        uint256 bobShares = feeVault.deposit(DEPOSIT_AMOUNT, bob);
        vm.stopPrank();

        // With 0% fees and equal deposits, shares should be equal
        assertEq(aliceShares, bobShares, "Equal deposits should yield equal shares");
        assertEq(feeVault.totalSupply(), aliceShares + bobShares, "Total supply should match");
    }

    function testNoFeeRoundTrip() public {
        vm.startPrank(alice);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);

        // Deposit
        uint256 shares = feeVault.deposit(DEPOSIT_AMOUNT, alice);

        // Immediately withdraw
        uint256 assetsReceived = feeVault.redeem(shares, alice, alice);

        // Should get same amount back (within 1 wei due to rounding)
        assertApproxEqAbs(assetsReceived, DEPOSIT_AMOUNT, 1, "Round trip should return same amount");

        vm.stopPrank();
    }

    // ============ Phase 2: Fee Tests ============

    function testEntryFeeCharged() public {
        // Set 1% entry fee
        feeVault.setEntryFee(ONE_PERCENT);

        vm.startPrank(alice);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);

        uint256 sharesBefore = feeVault.balanceOf(alice);
        feeVault.deposit(DEPOSIT_AMOUNT, alice);

        // Calculate expected fee: 1% of 1000 = 10
        uint256 expectedFee = (DEPOSIT_AMOUNT * ONE_PERCENT) / (ONE_PERCENT + 10000);
        uint256 expectedAssets = DEPOSIT_AMOUNT - expectedFee;

        assertEq(asset.balanceOf(feeRecipient), expectedFee, "Fee recipient should receive 1%");
        assertApproxEqAbs(
            feeVault.totalAssets(),
            expectedAssets,
            1,
            "Total assets should be deposit minus fee"
        );

        vm.stopPrank();
    }

    function testExitFeeCharged() public {
        // First deposit without fee
        vm.startPrank(alice);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);
        uint256 shares = feeVault.deposit(DEPOSIT_AMOUNT, alice);

        // Set 1% exit fee
        vm.stopPrank();
        feeVault.setExitFee(ONE_PERCENT);
        vm.startPrank(alice);

        uint256 balanceBefore = asset.balanceOf(alice);
        uint256 assetsReceived = feeVault.redeem(shares, alice, alice);

        // Calculate expected fee: 1% of assets
        uint256 expectedFee = (DEPOSIT_AMOUNT * ONE_PERCENT) / 10000;
        uint256 expectedAssets = DEPOSIT_AMOUNT - expectedFee;

        assertEq(asset.balanceOf(feeRecipient), expectedFee, "Fee recipient should receive 1%");
        assertApproxEqAbs(assetsReceived, expectedAssets, 2, "Should receive assets minus fee");

        vm.stopPrank();
    }

    function testBothFeesCharged() public {
        // Set both fees
        feeVault.setEntryFee(ONE_PERCENT);
        feeVault.setExitFee(ONE_PERCENT);

        vm.startPrank(alice);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);

        // Deposit with entry fee
        uint256 shares = feeVault.deposit(DEPOSIT_AMOUNT, alice);
        uint256 feesAfterDeposit = asset.balanceOf(feeRecipient);

        // Withdraw with exit fee
        feeVault.redeem(shares, alice, alice);
        uint256 feesAfterWithdraw = asset.balanceOf(feeRecipient);

        // Both fees should have been charged
        assertGt(feesAfterDeposit, 0, "Entry fee should be collected");
        assertGt(feesAfterWithdraw, feesAfterDeposit, "Exit fee should also be collected");

        vm.stopPrank();
    }

    function testMaxFeeRejected() public {
        // Try to set fee above max (10%)
        vm.expectRevert(FeeVaultWrapper.FeeTooHigh.selector);
        feeVault.setEntryFee(TEN_PERCENT + 1);

        vm.expectRevert(FeeVaultWrapper.FeeTooHigh.selector);
        feeVault.setExitFee(TEN_PERCENT + 1);
    }

    function testMaxFeeAccepted() public {
        // Max fee (10%) should work
        feeVault.setEntryFee(TEN_PERCENT);
        feeVault.setExitFee(TEN_PERCENT);

        assertEq(feeVault.entryFeeBps(), TEN_PERCENT, "Entry fee should be set");
        assertEq(feeVault.exitFeeBps(), TEN_PERCENT, "Exit fee should be set");
    }

    function testFeeRecipientUpdate() public {
        address newRecipient = makeAddr("newRecipient");

        feeVault.setFeeRecipient(newRecipient);

        assertEq(feeVault.feeRecipient(), newRecipient, "Fee recipient should be updated");
    }

    function testInvalidFeeRecipient() public {
        vm.expectRevert(FeeVaultWrapper.InvalidFeeRecipient.selector);
        feeVault.setFeeRecipient(address(0));
    }

    function testOnlyOwnerCanSetFees() public {
        vm.startPrank(alice);

        vm.expectRevert();
        feeVault.setEntryFee(ONE_PERCENT);

        vm.expectRevert();
        feeVault.setExitFee(ONE_PERCENT);

        vm.expectRevert();
        feeVault.setFeeRecipient(alice);

        vm.stopPrank();
    }

    // ============ Phase 3: Integration Tests ============

    function testBurveVaultE4626Integration() public {
        // Deploy diamond
        _newDiamond();

        // Add fee vault to Burve system
        vm.startPrank(owner);
        vaultFacet.addVault(address(asset), address(feeVault), VaultType.E4626);

        // Fast forward 5 days for timelock
        vm.warp(block.timestamp + 5 days + 1);

        // Accept vault
        vaultFacet.acceptVault(address(asset));
        vm.stopPrank();

        // User adds value through Burve
        vm.startPrank(alice);
        asset.approve(diamond, DEPOSIT_AMOUNT);

        uint256 burveValue = valueFacet.addValueSingle(
            alice,  // recipient
            3,      // closureId (first closure with 2 tokens)
            uint128(DEPOSIT_AMOUNT),  // value
            0,      // bgtValue
            address(asset),  // token
            type(uint128).max  // maxRequired
        );

        assertGt(burveValue, 0, "Should receive Burve value");
        assertEq(feeVault.balanceOf(diamond), feeVault.totalSupply(), "Diamond should hold all shares");

        vm.stopPrank();
    }

    function testBurveWithFeesActive() public {
        // Set 1% entry fee
        feeVault.setEntryFee(ONE_PERCENT);

        // Deploy diamond and add vault
        _newDiamond();
        vm.startPrank(owner);
        vaultFacet.addVault(address(asset), address(feeVault), VaultType.E4626);
        vm.warp(block.timestamp + 5 days + 1);
        vaultFacet.acceptVault(address(asset));
        vm.stopPrank();

        // Alice deposits through Burve
        vm.startPrank(alice);
        asset.approve(diamond, DEPOSIT_AMOUNT);
        uint256 aliceValue = valueFacet.addValueSingle(
            alice,
            3,
            uint128(DEPOSIT_AMOUNT),
            0,
            address(asset),
            type(uint128).max
        );

        // Bob deposits same amount
        vm.stopPrank();
        vm.startPrank(bob);
        asset.approve(diamond, DEPOSIT_AMOUNT);
        uint256 bobValue = valueFacet.addValueSingle(
            bob,
            3,
            uint128(DEPOSIT_AMOUNT),
            0,
            address(asset),
            type(uint128).max
        );

        // Values should be equal since both paid same fee
        assertEq(aliceValue, bobValue, "Equal deposits should yield equal Burve value");

        // Fee should have been collected
        assertGt(asset.balanceOf(feeRecipient), 0, "Fees should be collected");

        vm.stopPrank();
    }

    function testVaultE4626HandlesDiscountFactor() public {
        // Set 1% entry fee (creates discount factor)
        feeVault.setEntryFee(ONE_PERCENT);

        // Test the discount factor calculation that VaultE4626 uses
        // From E4626.sol line 59-61: previewRedeem(previewDeposit(1 << 128))
        uint256 depositAmount = 1 << 128;
        uint256 shares = feeVault.previewDeposit(depositAmount);
        uint256 assetsOut = feeVault.previewRedeem(shares);

        // assetsOut should be less than depositAmount due to fee
        assertLt(assetsOut, depositAmount, "Discount factor should reflect fee");

        // Calculate expected discount
        uint256 expectedFee = (depositAmount * ONE_PERCENT) / (ONE_PERCENT + 10000);
        assertApproxEqAbs(assetsOut, depositAmount - expectedFee, 100, "Discount should match fee");
    }

    // ============ Edge Cases ============

    function testZeroAmountDeposit() public {
        vm.startPrank(alice);
        asset.approve(address(feeVault), 0);

        // Should not revert, just do nothing
        uint256 shares = feeVault.deposit(0, alice);
        assertEq(shares, 0, "Zero deposit should yield zero shares");

        vm.stopPrank();
    }

    function testDustAmountDeposit() public {
        feeVault.setEntryFee(ONE_PERCENT);

        vm.startPrank(alice);
        asset.approve(address(feeVault), 1);

        // Even with 1 wei, should handle correctly
        uint256 shares = feeVault.deposit(1, alice);

        // May get 0 shares due to rounding, but shouldn't revert
        assertEq(feeVault.balanceOf(alice), shares, "Should handle dust amount");

        vm.stopPrank();
    }

    function testMultipleUsersInteracting() public {
        feeVault.setEntryFee(ONE_PERCENT);

        address[] memory users = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            asset.mint(users[i], DEPOSIT_AMOUNT);
        }

        // All users deposit
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(users[i]);
            asset.approve(address(feeVault), DEPOSIT_AMOUNT);
            feeVault.deposit(DEPOSIT_AMOUNT, users[i]);
            vm.stopPrank();
        }

        uint256 totalSupply = feeVault.totalSupply();
        assertGt(totalSupply, 0, "Total supply should be positive");

        // All users withdraw
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(users[i]);
            uint256 shares = feeVault.balanceOf(users[i]);
            feeVault.redeem(shares, users[i], users[i]);
            vm.stopPrank();
        }

        assertEq(feeVault.totalSupply(), 0, "All shares should be redeemed");
    }

    function testPreviewFunctionsMatchActual() public {
        feeVault.setEntryFee(ONE_PERCENT);

        vm.startPrank(alice);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);

        // Preview deposit
        uint256 expectedShares = feeVault.previewDeposit(DEPOSIT_AMOUNT);

        // Actual deposit
        uint256 actualShares = feeVault.deposit(DEPOSIT_AMOUNT, alice);

        assertApproxEqAbs(expectedShares, actualShares, 1, "Preview should match actual deposit");

        // Preview redeem
        uint256 expectedAssets = feeVault.previewRedeem(actualShares);

        // Set exit fee
        vm.stopPrank();
        feeVault.setExitFee(ONE_PERCENT);
        vm.startPrank(alice);

        // Actual redeem
        uint256 actualAssets = feeVault.redeem(actualShares, alice, alice);

        assertApproxEqAbs(expectedAssets, actualAssets, 2, "Preview should match actual redeem");

        vm.stopPrank();
    }

    function testTotalAssetsAccurate() public {
        // Deposit from multiple users
        vm.startPrank(alice);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);
        feeVault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        asset.approve(address(feeVault), DEPOSIT_AMOUNT);
        feeVault.deposit(DEPOSIT_AMOUNT, bob);
        vm.stopPrank();

        // Total assets should match sum of deposits (no fees)
        assertEq(feeVault.totalAssets(), DEPOSIT_AMOUNT * 2, "Total assets should match deposits");

        // Underlying vault balance should also match
        uint256 underlyingShares = underlyingVault.balanceOf(address(feeVault));
        uint256 underlyingAssets = underlyingVault.convertToAssets(underlyingShares);
        assertEq(underlyingAssets, DEPOSIT_AMOUNT * 2, "Underlying assets should match");
    }

    function testFeeEventsEmitted() public {
        // Test EntryFeeUpdated event
        vm.expectEmit(true, true, true, true);
        emit FeeVaultWrapper.EntryFeeUpdated(0, ONE_PERCENT);
        feeVault.setEntryFee(ONE_PERCENT);

        // Test ExitFeeUpdated event
        vm.expectEmit(true, true, true, true);
        emit FeeVaultWrapper.ExitFeeUpdated(0, ONE_PERCENT);
        feeVault.setExitFee(ONE_PERCENT);

        // Test FeeRecipientUpdated event
        address newRecipient = makeAddr("newRecipient");
        vm.expectEmit(true, true, true, true);
        emit FeeVaultWrapper.FeeRecipientUpdated(feeRecipient, newRecipient);
        feeVault.setFeeRecipient(newRecipient);
    }

    function testViewFunctions() public {
        assertEq(feeVault.getUnderlyingVault(), address(underlyingVault), "Should return underlying vault");

        (uint16 entry, uint16 exit, address recipient) = feeVault.getFeeConfig();
        assertEq(entry, 0, "Initial entry fee should be 0");
        assertEq(exit, 0, "Initial exit fee should be 0");
        assertEq(recipient, feeRecipient, "Fee recipient should match");

        // Update and check again
        feeVault.setEntryFee(ONE_PERCENT);
        feeVault.setExitFee(ONE_PERCENT * 2);

        (entry, exit, recipient) = feeVault.getFeeConfig();
        assertEq(entry, ONE_PERCENT, "Entry fee should be updated");
        assertEq(exit, ONE_PERCENT * 2, "Exit fee should be updated");
    }

    // ============ Fuzz Tests ============

    function testFuzz_DepositWithVariousFees(uint16 feeBps, uint128 amount) public {
        // Bound inputs
        feeBps = uint16(bound(feeBps, 0, TEN_PERCENT));
        amount = uint128(bound(amount, 1e18, 100_000e18));

        feeVault.setEntryFee(feeBps);

        vm.startPrank(alice);
        asset.approve(address(feeVault), amount);

        uint256 shares = feeVault.deposit(amount, alice);

        // Basic invariants
        assertGe(feeVault.balanceOf(alice), 0, "Should have non-negative shares");
        assertLe(feeVault.totalAssets(), amount, "Total assets should not exceed deposit");

        vm.stopPrank();
    }

    function testFuzz_RoundTrip(uint128 amount) public {
        // Bound amount to reasonable range
        amount = uint128(bound(amount, 1e18, 100_000e18));

        vm.startPrank(alice);
        asset.approve(address(feeVault), amount);

        uint256 shares = feeVault.deposit(amount, alice);
        uint256 assetsOut = feeVault.redeem(shares, alice, alice);

        // Should get same amount back (within rounding)
        assertApproxEqAbs(assetsOut, amount, 2, "Round trip should return same amount");

        vm.stopPrank();
    }
}
