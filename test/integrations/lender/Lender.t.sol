// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "../../facets/MultiSetup.u.sol";
import {Lender} from "../../../src/integrations/lender/Lender.sol";
import {PositionProxy} from "../../../src/integrations/lender/PositionProxy.sol";
import {InterestRateModel} from "../../../src/integrations/lender/InterestRateModel.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {IBurveMultiValue} from "../../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "../../../src/multi/facets/ValueTokenFacet.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

/// @notice Mock Chainlink aggregator for testing.
contract MockAggregator {
    int256 public price;
    uint8 public _decimals;
    uint256 public updatedAt;

    constructor(int256 _price, uint8 decimals_) {
        price = _price;
        _decimals = decimals_;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
    {
        return (1, price, block.timestamp, updatedAt, 1);
    }
}

contract TestLender is MultiSetupTest {
    Lender lender;
    MockAggregator[] oracles;

    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(3);
        _fundAccount(alice);
        _fundAccount(bob);
        _fundAccount(address(this));
        vm.startPrank(owner);
        _initializeClosure(0x3, 1_000_000e18); // tokens 0,1
        _initializeClosure(0x7, 1_000_000e18); // tokens 0,1,2
        vm.stopPrank();

        // Deploy Lender
        lender = new Lender();

        // Allow pool
        lender.setPoolAllowed(diamond, true);

        // Deploy mock oracles — all tokens at $1.00 (1e8 Chainlink precision, 8 decimals)
        for (uint256 i = 0; i < tokens.length; i++) {
            MockAggregator oracle = new MockAggregator(1e8, 8);
            oracles.push(oracle);
            lender.setPriceFeed(tokens[i], address(oracle), 18);
        }
    }

    // ============================================================
    //                     HELPERS
    // ============================================================

    function _openPosition(uint16 cid, uint128 depositValue) internal returns (uint256 posValue) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if ((1 << i) & cid > 0) {
                MockERC20(tokens[i]).mint(address(this), uint256(depositValue) * 2);
                IERC20(tokens[i]).approve(diamond, type(uint256).max);
            }
        }
        uint256[MAX_TOKENS] memory addLimits;
        IBurveMultiValue(diamond).addValue(address(this), cid, depositValue, 0, addLimits);
        (posValue,) = ValueTokenFacet(diamond).balanceOf(address(this), cid);
    }

    function _depositCollateral(uint16 cid, uint128 depositValue) internal returns (uint256 positionId, uint256 posValue) {
        posValue = _openPosition(cid, depositValue);
        ValueTokenFacet(diamond).approve(address(lender), cid, posValue, 0);
        positionId = lender.depositCollateral(diamond, cid, posValue, 0);
    }

    function _fundLendingPool(address token, uint256 amount) internal {
        MockERC20(token).mint(address(this), amount);
        IERC20(token).approve(address(lender), amount);
        lender.depositLiquidity(token, amount);
    }

    // ============================================================
    //                     POOL ALLOWLIST TESTS
    // ============================================================

    function testRevertDepositNotAllowedPool() public {
        address fakePool = makeAddr("fakePool");
        // Trying to deposit with a non-allowlisted pool should revert
        vm.expectRevert(Lender.PoolNotAllowed.selector);
        lender.depositCollateral(fakePool, 3, 1e18, 0);
    }

    function testPoolAllowlistToggle() public {
        address pool2 = makeAddr("pool2");
        assertFalse(lender.allowedPools(pool2));
        lender.setPoolAllowed(pool2, true);
        assertTrue(lender.allowedPools(pool2));
        lender.setPoolAllowed(pool2, false);
        assertFalse(lender.allowedPools(pool2));
    }

    // ============================================================
    //                     LENDING POOL TESTS
    // ============================================================

    function testDepositLiquidity() public {
        address token = tokens[0];
        MockERC20(token).mint(address(this), 10_000e18);
        IERC20(token).approve(address(lender), 10_000e18);

        lender.depositLiquidity(token, 1_000e18);

        (uint256 totalDeposited,,,,, uint256 totalShares) = lender.lendingPools(token);
        assertEq(totalDeposited, 1_000e18);
        assertEq(totalShares, 1_000e18);
        assertEq(lender.lpShares(token, address(this)), 1_000e18);
    }

    function testWithdrawLiquidity() public {
        address token = tokens[0];
        MockERC20(token).mint(address(this), 10_000e18);
        IERC20(token).approve(address(lender), 10_000e18);

        lender.depositLiquidity(token, 1_000e18);

        uint256 balBefore = IERC20(token).balanceOf(address(this));
        lender.withdrawLiquidity(token, 500e18);
        uint256 balAfter = IERC20(token).balanceOf(address(this));

        assertEq(balAfter - balBefore, 500e18);
        assertEq(lender.lpShares(token, address(this)), 500e18);
    }

    // ============================================================
    //                     COLLATERAL TESTS
    // ============================================================

    function testDepositCollateral() public {
        uint16 cid = 3;
        (uint256 positionId, uint256 posValue) = _depositCollateral(cid, 1000e18);

        (address borrower, address pool, uint16 closureId, address proxy, uint256 depValue, uint256 depBgtValue) = lender.positions(positionId);

        assertEq(borrower, address(this));
        assertEq(pool, diamond);
        assertEq(closureId, cid);
        assertTrue(proxy != address(0));
        assertEq(depValue, posValue);
        assertEq(depBgtValue, 0);
    }

    function testWithdrawCollateral() public {
        uint16 cid = 3;
        (uint256 positionId, uint256 posValue) = _depositCollateral(cid, 1000e18);

        lender.withdrawCollateral(positionId, posValue / 2, 0);

        (,,,, uint256 depValue,) = lender.positions(positionId);
        assertEq(depValue, posValue - posValue / 2);

        (uint256 userValue,) = ValueTokenFacet(diamond).balanceOf(address(this), cid);
        assertEq(userValue, posValue / 2);
    }

    // ============================================================
    //                     BORROW / REPAY TESTS
    // ============================================================

    function testBorrowAndRepay() public {
        address borrowToken = tokens[0];

        // Fund lending pool
        _fundLendingPool(borrowToken, 10_000e18);

        // Deposit collateral
        (uint256 positionId,) = _depositCollateral(3, 1000e18);

        // Borrow
        uint256 borrowAmount = 100e18;
        uint256 balBefore = IERC20(borrowToken).balanceOf(address(this));
        lender.borrow(positionId, borrowToken, borrowAmount);
        uint256 balAfter = IERC20(borrowToken).balanceOf(address(this));
        assertEq(balAfter - balBefore, borrowAmount);

        // Repay
        IERC20(borrowToken).approve(address(lender), borrowAmount);
        lender.repay(positionId, borrowToken, borrowAmount);

        assertEq(lender.currentBorrow(positionId, borrowToken), 0);
    }

    function testRevertExceedsMaxLTV() public {
        address borrowToken = tokens[0];
        _fundLendingPool(borrowToken, 100_000e18);

        (uint256 positionId,) = _depositCollateral(3, 1000e18);

        // Try to borrow too much (>80% of collateral value)
        uint256 colUSD = lender.collateralValueUSD(positionId);
        uint256 tooMuch = colUSD; // 100% of collateral — way over 80%

        vm.expectRevert(Lender.ExceedsMaxLTV.selector);
        lender.borrow(positionId, borrowToken, tooMuch);
    }

    function testRevertBorrowNotOwner() public {
        address borrowToken = tokens[0];
        _fundLendingPool(borrowToken, 10_000e18);

        (uint256 positionId,) = _depositCollateral(3, 1000e18);

        vm.prank(alice);
        vm.expectRevert(Lender.NotPositionOwner.selector);
        lender.borrow(positionId, borrowToken, 100e18);
    }

    // ============================================================
    //                     INTEREST ACCRUAL TESTS
    // ============================================================

    function testInterestAccrual() public {
        address borrowToken = tokens[0];
        _fundLendingPool(borrowToken, 10_000e18);

        (uint256 positionId,) = _depositCollateral(3, 1000e18);
        lender.borrow(positionId, borrowToken, 100e18);

        uint256 borrowBefore = lender.currentBorrow(positionId, borrowToken);

        // Advance time by 1 year
        vm.warp(block.timestamp + 365.25 days);

        uint256 borrowAfter = lender.currentBorrow(positionId, borrowToken);
        assertGt(borrowAfter, borrowBefore, "interest should accrue");
        console2.log("borrow before:", borrowBefore);
        console2.log("borrow after 1yr:", borrowAfter);
    }

    // ============================================================
    //                     LIQUIDATION TESTS
    // ============================================================

    function testLiquidation() public {
        address borrowToken = tokens[0];
        _fundLendingPool(borrowToken, 100_000e18);

        (uint256 positionId,) = _depositCollateral(3, 1000e18);

        // Borrow near max LTV
        uint256 maxBorrow = lender.maxBorrowable(positionId, borrowToken);
        lender.borrow(positionId, borrowToken, maxBorrow);

        // Create asymmetric price movement to make position unhealthy:
        // Drop token1 (collateral component) drastically while keeping token0 (borrow token) stable.
        // Closure 3 = token0 + token1, so collateral is 50/50. If token1 drops to $0.01:
        // Collateral ≈ $500 (token0) + $5 (token1) = $505
        // Debt = 800 token0 * $1 = $800
        // HF = $505 * 0.85 / $800 ≈ 0.536 — unhealthy
        oracles[1].setPrice(0.01e8); // token1 crashes to $0.01

        // Verify unhealthy
        uint256 hf = lender.healthFactor(positionId);
        assertLt(hf, 1e18, "position should be unhealthy");

        // Liquidator repays some debt and seizes collateral
        uint256 owed = lender.currentBorrow(positionId, borrowToken);
        uint256 repayAmount = owed / 2; // partial liquidation

        MockERC20(borrowToken).mint(alice, repayAmount);
        vm.startPrank(alice);
        IERC20(borrowToken).approve(address(lender), repayAmount);
        lender.liquidate(positionId, borrowToken, repayAmount);
        vm.stopPrank();

        // Liquidator should have received value position
        (uint256 liquidatorValue,) = ValueTokenFacet(diamond).balanceOf(alice, 3);
        assertGt(liquidatorValue, 0, "liquidator should receive value");
        console2.log("liquidator received value:", liquidatorValue);
    }

    function testRevertLiquidateHealthyPosition() public {
        address borrowToken = tokens[0];
        _fundLendingPool(borrowToken, 100_000e18);

        (uint256 positionId,) = _depositCollateral(3, 1000e18);
        lender.borrow(positionId, borrowToken, 100e18);

        // Position is healthy — should revert
        MockERC20(borrowToken).mint(alice, 100e18);
        vm.startPrank(alice);
        IERC20(borrowToken).approve(address(lender), 100e18);
        vm.expectRevert(Lender.PositionHealthy.selector);
        lender.liquidate(positionId, borrowToken, 50e18);
        vm.stopPrank();
    }

    function testRevertExcessRepayment() public {
        address borrowToken = tokens[0];
        _fundLendingPool(borrowToken, 100_000e18);

        (uint256 positionId,) = _depositCollateral(3, 1000e18);

        // Borrow near max LTV so the position goes unhealthy after price crash
        uint256 maxBorrow = lender.maxBorrowable(positionId, borrowToken);
        lender.borrow(positionId, borrowToken, maxBorrow);

        // Crash token1 to make position unhealthy
        oracles[1].setPrice(0.01e8);

        // Try to repay more than total owed
        uint256 owed = lender.currentBorrow(positionId, borrowToken);
        uint256 excessAmount = owed + 100e18;

        MockERC20(borrowToken).mint(alice, excessAmount);
        vm.startPrank(alice);
        IERC20(borrowToken).approve(address(lender), excessAmount);
        vm.expectRevert(Lender.ExcessRepayment.selector);
        lender.liquidate(positionId, borrowToken, excessAmount);
        vm.stopPrank();
    }

    // ============================================================
    //                     WITHDRAWAL + HEALTH CHECK TESTS
    // ============================================================

    function testRevertWithdrawPushesUnhealthy() public {
        address borrowToken = tokens[0];
        _fundLendingPool(borrowToken, 100_000e18);

        (uint256 positionId, uint256 posValue) = _depositCollateral(3, 1000e18);
        uint256 maxBorrow = lender.maxBorrowable(positionId, borrowToken);
        lender.borrow(positionId, borrowToken, maxBorrow);

        // Try to withdraw any collateral — should fail since already at max LTV
        vm.expectRevert(Lender.ExceedsMaxLTV.selector);
        lender.withdrawCollateral(positionId, posValue / 10, 0);
    }

    // ============================================================
    //                     COLLATERAL FACTOR TESTS
    // ============================================================

    function testCollateralFactorReducesBorrowing() public {
        address borrowToken = tokens[0];
        _fundLendingPool(borrowToken, 100_000e18);

        (uint256 positionId,) = _depositCollateral(3, 1000e18);

        uint256 maxBorrowFull = lender.maxBorrowable(positionId, borrowToken);

        // Set collateral factor to 50% for all tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            lender.setCollateralFactor(tokens[i], 5e17); // 50%
        }

        uint256 maxBorrowHalf = lender.maxBorrowable(positionId, borrowToken);
        assertLt(maxBorrowHalf, maxBorrowFull, "50% factor should reduce borrowable");
        console2.log("full max borrow:", maxBorrowFull);
        console2.log("half max borrow:", maxBorrowHalf);
    }

    // ============================================================
    //                     EARNINGS PASS-THROUGH TESTS
    // ============================================================

    function testCollectPositionEarnings() public {
        (uint256 positionId,) = _depositCollateral(3, 1000e18);

        // Just verify it doesn't revert — earnings require trading fees to accumulate
        lender.collectPositionEarnings(positionId, address(this));
    }

    // ============================================================
    //                     VIEW FUNCTION TESTS
    // ============================================================

    function testHealthFactorNoDebt() public {
        (uint256 positionId,) = _depositCollateral(3, 1000e18);
        assertEq(lender.healthFactor(positionId), type(uint256).max);
    }

    function testCollateralValueUSD() public {
        (uint256 positionId,) = _depositCollateral(3, 1000e18);
        uint256 colUSD = lender.collateralValueUSD(positionId);
        assertGt(colUSD, 0, "collateral should have value");
        console2.log("collateral USD:", colUSD);
    }

    function testProxyAddress() public {
        (uint256 positionId,) = _depositCollateral(3, 1000e18);
        (,,, address actualProxy,,) = lender.positions(positionId);
        address computedProxy = lender.getProxyAddress(positionId);
        assertEq(actualProxy, computedProxy, "computed proxy should match actual");
    }

    // ============================================================
    //                     ADDITIONAL EDGE CASE TESTS
    // ============================================================

    function testRepayAll() public {
        address borrowToken = tokens[0];
        _fundLendingPool(borrowToken, 10_000e18);

        (uint256 positionId,) = _depositCollateral(3, 1000e18);
        lender.borrow(positionId, borrowToken, 100e18);

        // Advance time to accrue interest
        vm.warp(block.timestamp + 30 days);

        // Repay with type(uint256).max should repay exact owed amount
        uint256 owed = lender.currentBorrow(positionId, borrowToken);
        assertGt(owed, 100e18, "interest should have accrued");

        MockERC20(borrowToken).mint(address(this), owed);
        IERC20(borrowToken).approve(address(lender), type(uint256).max);
        lender.repay(positionId, borrowToken, type(uint256).max);

        assertEq(lender.currentBorrow(positionId, borrowToken), 0, "debt should be zero after repayAll");
    }

    function testMultiTokenBorrow() public {
        // Use 3-token closure (0x7) and borrow in two different tokens
        _fundLendingPool(tokens[0], 100_000e18);
        _fundLendingPool(tokens[1], 100_000e18);

        (uint256 positionId,) = _depositCollateral(7, 1000e18);

        lender.borrow(positionId, tokens[0], 50e18);
        lender.borrow(positionId, tokens[1], 50e18);

        uint256 debt0 = lender.currentBorrow(positionId, tokens[0]);
        uint256 debt1 = lender.currentBorrow(positionId, tokens[1]);
        assertEq(debt0, 50e18, "should owe 50 of token0");
        assertEq(debt1, 50e18, "should owe 50 of token1");

        // Borrow value USD should reflect both debts
        uint256 totalDebtUSD = lender.borrowValueUSD(positionId);
        assertGt(totalDebtUSD, 99e18, "total debt should be ~$100");

        // Health factor should account for both debts
        uint256 hf = lender.healthFactor(positionId);
        assertGt(hf, 1e18, "should be healthy");
        console2.log("multi-token health factor:", hf);
    }

    function testRevertStaleOracle() public {
        _fundLendingPool(tokens[0], 10_000e18);

        (uint256 positionId,) = _depositCollateral(3, 1000e18);

        // Advance time past oracle staleness threshold (1 hour)
        // Oracle updatedAt stays at the old block.timestamp
        vm.warp(block.timestamp + 2 hours);

        // Borrowing should revert due to stale oracle in health check
        vm.expectRevert();
        lender.borrow(positionId, tokens[0], 100e18);
    }

    function testFullLiquidation() public {
        address borrowToken = tokens[0];
        _fundLendingPool(borrowToken, 100_000e18);

        (uint256 positionId,) = _depositCollateral(3, 1000e18);

        // Borrow near max
        uint256 maxBorrow = lender.maxBorrowable(positionId, borrowToken);
        lender.borrow(positionId, borrowToken, maxBorrow);

        // Crash token1 to make position very unhealthy
        oracles[1].setPrice(0.01e8);

        // Liquidator repays ALL debt
        uint256 owed = lender.currentBorrow(positionId, borrowToken);
        MockERC20(borrowToken).mint(alice, owed);
        vm.startPrank(alice);
        IERC20(borrowToken).approve(address(lender), owed);
        lender.liquidate(positionId, borrowToken, owed);
        vm.stopPrank();

        // After full liquidation, position should have reduced collateral
        (,,,, uint256 depValue,) = lender.positions(positionId);
        // Debt is fully repaid
        assertEq(lender.currentBorrow(positionId, borrowToken), 0, "debt should be zero");
        console2.log("remaining collateral after full liquidation:", depValue);

        // Liquidator should have received value
        (uint256 liquidatorValue,) = ValueTokenFacet(diamond).balanceOf(alice, 3);
        assertGt(liquidatorValue, 0, "liquidator should receive value");
    }

    function testRevertNotAuthorizedLooper() public {
        // Non-authorized address tries to use depositCollateralFor
        vm.expectRevert(Lender.NotAuthorizedLooper.selector);
        lender.depositCollateralFor(alice, diamond, 3, 100e18, 0);
    }
}
