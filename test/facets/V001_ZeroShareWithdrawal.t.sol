// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {FullMath} from "../../src/FullMath.sol";
import {ClosureId} from "../../src/multi/closure/Id.sol";
import {VaultE4626, VaultE4626Impl} from "../../src/multi/vertex/E4626.sol";
import {VaultTemp} from "../../src/multi/vertex/VaultPointer.sol";

/// @notice Harness contract that exposes E4626 vault operations directly for testing.
///         Holds a VaultE4626 in storage and delegates to VaultE4626Impl.
contract E4626Harness {
    using VaultE4626Impl for VaultE4626;

    VaultE4626 internal vault;

    function init(address token, address vaultAddr) external {
        vault.init(token, vaultAddr);
    }

    function deposit(ClosureId cid, uint256 amount) external {
        VaultTemp memory temp;
        vault.fetch(temp);
        vault.deposit(temp, cid, amount);
        vault.commit(temp);
    }

    function withdraw(ClosureId cid, uint256 amount) external {
        VaultTemp memory temp;
        vault.fetch(temp);
        vault.withdraw(temp, cid, amount);
        vault.commit(temp);
    }

    function balance(ClosureId cid) external view returns (uint128) {
        VaultTemp memory temp;
        vault.fetch(temp);
        return vault.balance(temp, cid, false);
    }

    function getShares(ClosureId cid) external view returns (uint256) {
        return vault.shares[cid];
    }

    function getTotalShares() external view returns (uint256) {
        return vault.totalShares;
    }

    function getTotalAssets() external view returns (uint256) {
        VaultTemp memory temp;
        vault.fetch(temp);
        return temp.vars[0];
    }
}

/// @title V-001 Fix Verification: ERC4626 vault withdrawal share rounding
/// @notice Verifies that after the fix (mulDivRoundingUp in E4626.withdraw),
///         small withdrawals always burn at least 1 share, preventing the
///         zero-share withdrawal attack.
contract V001ZeroShareWithdrawalTest is Test {
    MockERC20 token;
    MockERC4626 vault;
    E4626Harness harness;

    ClosureId cidA = ClosureId.wrap(1);
    ClosureId cidB = ClosureId.wrap(2);

    function setUp() public {
        token = new MockERC20("Test Token", "TEST", 18);
        vault = new MockERC4626(ERC20(address(token)), "Test Vault", "vTEST");
        harness = new E4626Harness();
        harness.init(address(token), address(vault));
    }

    /// @notice After fix: 1-wei withdrawal with yield MUST burn at least 1 share.
    function testSmallWithdrawalBurnsShares() public {
        uint256 depositAmount = 100e18;

        // Deposit for two closures
        token.mint(address(harness), depositAmount * 2);
        harness.deposit(cidA, depositAmount);
        harness.deposit(cidB, depositAmount);

        // Simulate yield (double vault assets)
        token.mint(address(vault), 100e18);

        uint256 totalAssets = harness.getTotalAssets();
        uint256 totalShares = harness.getTotalShares();
        assertGt(totalAssets, totalShares, "totalAssets > totalShares after yield");

        // Withdraw 1 wei — must burn >= 1 share
        uint256 sharesBefore = harness.getShares(cidA);
        harness.withdraw(cidA, 1);
        uint256 sharesAfter = harness.getShares(cidA);

        assertLt(sharesAfter, sharesBefore, "Fix: shares must decrease for any positive withdrawal");
        assertEq(sharesBefore - sharesAfter, 1, "Fix: exactly 1 share burned for 1-wei withdrawal");
    }

    /// @notice After fix: repeated small withdrawals properly reduce shares,
    ///         so the victim's balance is NOT reduced by the attack.
    function testRepeatedSmallWithdrawalsCannotStealFromVictim() public {
        uint256 depositAmount = 100e18;

        // Deposit for two closures
        token.mint(address(harness), depositAmount * 2);
        harness.deposit(cidA, depositAmount);
        harness.deposit(cidB, depositAmount);

        // Simulate yield
        token.mint(address(vault), 100e18);

        uint256 balBPostYield = harness.balance(cidB);
        uint256 sharesABefore = harness.getShares(cidA);

        // Attacker does 200 x 1-wei withdrawals
        uint256 iterations = 200;
        for (uint256 i = 0; i < iterations; i++) {
            harness.withdraw(cidA, 1);
        }

        uint256 sharesAAfter = harness.getShares(cidA);
        uint256 balBAfter = harness.balance(cidB);

        // Attacker's shares decreased by at least 200 (1 per withdrawal, rounded up)
        assertEq(
            sharesABefore - sharesAAfter,
            iterations,
            "Fix: attacker lost 1 share per withdrawal"
        );

        // Victim's balance should be >= post-yield balance (victim gains slightly
        // since attacker's share fraction decreased while paying assets)
        assertGe(
            balBAfter,
            balBPostYield,
            "Fix: victim balance not decreased by attack"
        );
    }

    /// @notice After fix: withdrawal of exactly (totalAssets / totalShares) burns exactly 1 share.
    function testWithdrawalAtSharePriceBurnsOneShare() public {
        uint256 depositAmount = 100e18;

        token.mint(address(harness), depositAmount * 2);
        harness.deposit(cidA, depositAmount);
        harness.deposit(cidB, depositAmount);

        // 50% yield
        token.mint(address(vault), 100e18);

        uint256 totalAssets = harness.getTotalAssets();
        uint256 totalShares = harness.getTotalShares();

        // sharePrice = totalAssets / totalShares = 300e18 / 200e18 = 1.5
        // Withdraw exactly 1 share worth of assets (rounding down)
        uint256 oneShareValue = totalAssets / totalShares; // = 1 (rounds to 1 for 1.5)
        // Actually with large numbers: 299999999999999999999 / 200000000000000000000 = 1

        uint256 sharesBefore = harness.getShares(cidA);
        harness.withdraw(cidA, oneShareValue);
        uint256 sharesAfter = harness.getShares(cidA);

        // Should burn at least 1 share (rounding up)
        assertGe(
            sharesBefore - sharesAfter,
            1,
            "Should burn at least 1 share"
        );
    }

    /// @notice Ensure large withdrawals still work correctly after the fix.
    function testLargeWithdrawalStillWorks() public {
        uint256 depositAmount = 100e18;

        token.mint(address(harness), depositAmount * 2);
        harness.deposit(cidA, depositAmount);
        harness.deposit(cidB, depositAmount);

        // Yield
        token.mint(address(vault), 100e18);

        uint256 sharesABefore = harness.getShares(cidA);
        uint256 balABefore = harness.balance(cidA);

        // Withdraw a substantial amount (half of cidA's balance)
        uint256 withdrawAmt = balABefore / 2;
        harness.withdraw(cidA, withdrawAmt);

        uint256 sharesAAfter = harness.getShares(cidA);
        assertLt(sharesAAfter, sharesABefore, "Shares should decrease for large withdrawal");
        assertGt(sharesAAfter, 0, "Should still have some shares remaining");

        // Verify balance decreased proportionally
        uint256 balAAfter = harness.balance(cidA);
        assertLt(balAAfter, balABefore, "Balance should decrease after withdrawal");
    }

    /// @notice Deposits should still work correctly (rounding down for new shares).
    function testDepositRoundingUnchanged() public {
        uint256 depositAmount = 100e18;

        token.mint(address(harness), depositAmount * 3);
        harness.deposit(cidA, depositAmount);

        // Yield
        token.mint(address(vault), 50e18);

        // Deposit more — new shares should round DOWN (unchanged behavior)
        uint256 sharesBefore = harness.getShares(cidA);
        harness.deposit(cidA, depositAmount);
        uint256 sharesAfter = harness.getShares(cidA);

        uint256 newShares = sharesAfter - sharesBefore;
        // With yield, new shares < deposit amount (depositor gets less than 1:1)
        assertLt(newShares, depositAmount, "New deposit shares should be discounted by yield");
        assertGt(newShares, 0, "Should receive some shares");
    }
}
