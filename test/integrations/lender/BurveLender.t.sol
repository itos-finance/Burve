// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "../../facets/MultiSetup.u.sol";
import {BurveLender} from "../../../src/integrations/lender/BurveLender.sol";
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
    uint8 public decimals_;
    uint256 public updatedAt;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals_ = _decimals;
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
        return decimals_;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 _updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, price, block.timestamp, updatedAt, 1);
    }
}

contract TestBurveLender is MultiSetupTest {
    BurveLender lender;
    MockAggregator[] oracles;
    address constant ROUTER = address(0xDEAD);

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

        // Deploy BurveLender
        lender = new BurveLender(ROUTER);

        // Deploy mock oracles for each pool token
        // All tokens at $1.00 (1e8 Chainlink precision)
        for (uint256 i = 0; i < tokens.length; i++) {
            MockAggregator oracle = new MockAggregator(1e8, 8);
            oracles.push(oracle);
            lender.setPriceFeed(tokens[i], address(oracle), 18);
        }
    }

    /// @dev Helper to open a value position and return its value.
    function _openPosition(
        uint16 closureId,
        uint128 depositValue
    ) internal returns (uint256 posValue) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if ((1 << i) & closureId > 0) {
                MockERC20(tokens[i]).mint(address(this), uint256(depositValue) * 2);
                IERC20(tokens[i]).approve(diamond, type(uint256).max);
            }
        }
        uint256[MAX_TOKENS] memory addLimits;
        IBurveMultiValue(diamond).addValue(
            address(this),
            closureId,
            depositValue,
            0,
            addLimits
        );
        (posValue, ) = ValueTokenFacet(diamond).balanceOf(
            address(this),
            closureId
        );
    }

    /// @dev Helper to deposit collateral into BurveLender.
    function _depositCollateral(
        uint16 closureId,
        uint128 depositValue
    ) internal returns (uint256 positionId, uint256 posValue) {
        posValue = _openPosition(closureId, depositValue);

        // Approve BurveLender to transfer value
        ValueTokenFacet(diamond).approve(
            address(lender),
            closureId,
            posValue,
            0
        );

        positionId = lender.depositCollateral(diamond, closureId, posValue, 0);
    }

    // ============================================================
    //                     LENDING POOL TESTS
    // ============================================================

    function testDepositLiquidity() public {
        address token = tokens[0];

        MockERC20(token).mint(address(this), 10_000e18);
        IERC20(token).approve(address(lender), 10_000e18);

        lender.depositLiquidity(token, 1_000e18);

        (uint256 totalDeposited,,,,,uint256 totalShares) = lender.lendingPools(token);
        assertEq(totalDeposited, 1_000e18, "total deposited should be 1000");
        assertEq(totalShares, 1_000e18, "initial shares should equal deposit");
        assertEq(lender.lpShares(token, address(this)), 1_000e18, "lp shares should match");
    }

    function testWithdrawLiquidity() public {
        address token = tokens[0];

        MockERC20(token).mint(address(this), 10_000e18);
        IERC20(token).approve(address(lender), 10_000e18);

        lender.depositLiquidity(token, 1_000e18);

        uint256 balBefore = IERC20(token).balanceOf(address(this));
        lender.withdrawLiquidity(token, 500e18);
        uint256 balAfter = IERC20(token).balanceOf(address(this));

        assertEq(balAfter - balBefore, 500e18, "should receive 500 tokens back");
        assertEq(lender.lpShares(token, address(this)), 500e18, "shares should be reduced");
    }

    // ============================================================
    //                     COLLATERAL TESTS
    // ============================================================

    function testDepositCollateral() public {
        uint16 closureId = 3; // Two-token closure
        (uint256 positionId, uint256 posValue) = _depositCollateral(closureId, 1000e18);

        (address borrower, address pool, uint16 cid, address proxy, uint256 depValue, uint256 depBgtValue) = lender.positions(positionId);

        assertEq(borrower, address(this), "borrower should be this");
        assertEq(pool, diamond, "pool should be diamond");
        assertEq(cid, closureId, "closure should match");
        assertTrue(proxy != address(0), "proxy should be deployed");
        assertEq(depValue, posValue, "deposited value should match");
        assertEq(depBgtValue, 0, "no bgt value");
    }

    function testWithdrawCollateral() public {
        uint16 closureId = 3;
        (uint256 positionId, uint256 posValue) = _depositCollateral(closureId, 1000e18);

        // Withdraw half
        lender.withdrawCollateral(positionId, posValue / 2, 0);

        (,,,,uint256 depValue,) = lender.positions(positionId);
        assertEq(depValue, posValue - posValue / 2, "deposited value should decrease");

        // Check value returned to user
        (uint256 userValue, ) = ValueTokenFacet(diamond).balanceOf(address(this), closureId);
        assertEq(userValue, posValue / 2, "user should have half value back");
    }

    // ============================================================
    //                     BORROW / REPAY TESTS
    // ============================================================

    function testBorrowAndRepay() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 10_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 10_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 5_000e18);

        // Deposit collateral
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // Borrow
        uint256 colUSD = lender.collateralValueUSD(positionId);
        console2.log("collateral USD", colUSD);
        uint256 borrowAmount = 100e18; // Small borrow relative to collateral
        lender.borrow(positionId, borrowToken, borrowAmount);

        uint256 owed = lender.currentBorrow(positionId, borrowToken);
        assertEq(owed, borrowAmount, "owed should equal borrowed");

        // Check token received
        uint256 bal = IERC20(borrowToken).balanceOf(address(this));
        assertGe(bal, borrowAmount, "should have received borrowed tokens");

        // Repay
        IERC20(borrowToken).approve(address(lender), borrowAmount);
        lender.repay(positionId, borrowToken, borrowAmount);

        owed = lender.currentBorrow(positionId, borrowToken);
        assertEq(owed, 0, "owed should be zero after full repay");
    }

    function testBorrowExceedsLTV() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 100_000e18);

        // Deposit collateral
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        uint256 colUSD = lender.collateralValueUSD(positionId);

        // Try to borrow more than 80% LTV — should revert
        uint256 excessiveBorrow = colUSD; // 100% of collateral value
        vm.expectRevert(BurveLender.ExceedsMaxLTV.selector);
        lender.borrow(positionId, borrowToken, excessiveBorrow);
    }

    // ============================================================
    //                     INTEREST ACCRUAL TESTS
    // ============================================================

    function testInterestAccrual() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 10_000e18);

        // Deposit collateral and borrow
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);
        lender.borrow(positionId, borrowToken, 100e18);

        uint256 owedBefore = lender.currentBorrow(positionId, borrowToken);

        // Advance time by 1 year
        vm.warp(block.timestamp + 365.25 days);

        uint256 owedAfter = lender.currentBorrow(positionId, borrowToken);
        assertGt(owedAfter, owedBefore, "interest should accrue over time");
        console2.log("owed before (1yr)", owedBefore);
        console2.log("owed after (1yr)", owedAfter);
        console2.log("interest", owedAfter - owedBefore);
    }

    // ============================================================
    //                     HEALTH FACTOR / LIQUIDATION TESTS
    // ============================================================

    function testHealthFactor() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 10_000e18);

        // Deposit collateral and borrow
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // No debt = max health
        uint256 hf = lender.healthFactor(positionId);
        assertEq(hf, type(uint256).max, "no debt = max health factor");

        // Borrow some
        lender.borrow(positionId, borrowToken, 100e18);
        hf = lender.healthFactor(positionId);
        assertGt(hf, 1e18, "health factor should be > 1 after reasonable borrow");
        console2.log("health factor", hf);
    }

    function testLiquidationRevertsWhenHealthy() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 10_000e18);

        // Deposit collateral and borrow (healthy position)
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);
        lender.borrow(positionId, borrowToken, 100e18);

        // Attempt liquidation — should revert
        bytes[MAX_TOKENS] memory txData;
        address[] memory debtTokens = new address[](1);
        debtTokens[0] = borrowToken;

        vm.prank(bob);
        vm.expectRevert(BurveLender.PositionHealthy.selector);
        lender.liquidate(positionId, txData, debtTokens);
    }

    // ============================================================
    //                     INTEREST RATE MODEL TESTS
    // ============================================================

    function testBaseRate() public pure {
        uint256 rate = InterestRateModel.getBorrowRate(0, 1000e18);
        assertEq(rate, 2e16, "base rate should be 2%");
    }

    function testOptimalUtilizationRate() public pure {
        // 80% utilization
        uint256 rate = InterestRateModel.getBorrowRate(800e18, 1000e18);
        // Should be base (2%) + slope1 (4%) = 6%
        assertEq(rate, 6e16, "rate at 80% utilization should be 6%");
    }

    function testMaxUtilizationRate() public pure {
        // 100% utilization
        uint256 rate = InterestRateModel.getBorrowRate(1000e18, 1000e18);
        // Should be base (2%) + slope1 (4%) + slope2 (75%) = 81%
        assertEq(rate, 81e16, "rate at 100% utilization should be 81%");
    }

    // ============================================================
    //                     FEE COLLECTION TESTS
    // ============================================================

    function testCollectEarnings() public {
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // Earnings collection — may not have earnings in test env, but shouldn't revert
        lender.collectPositionEarnings(positionId, address(this));
    }

    // ============================================================
    //                     PROXY TESTS
    // ============================================================

    function testProxyDeployment() public {
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        (,,,address proxy,,) = lender.positions(positionId);
        assertTrue(proxy != address(0), "proxy should exist");
        assertEq(PositionProxy(proxy).lender(), address(lender), "proxy lender should be BurveLender");
    }

    function testProxyOnlyLender() public {
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        (,,,address proxy,,) = lender.positions(positionId);

        // Non-lender should not be able to execute
        vm.prank(alice);
        vm.expectRevert(PositionProxy.OnlyLender.selector);
        PositionProxy(proxy).execute(diamond, "");
    }

    // ============================================================
    //                     COLLATERAL FACTOR TESTS
    // ============================================================

    function testSetCollateralFactor() public {
        address token = tokens[0];

        // Owner can set factor
        lender.setCollateralFactor(token, 75e16); // 75%
        assertEq(lender.collateralFactors(token), 75e16, "factor should be 75%");

        // Reset to default (0 = 100%)
        lender.setCollateralFactor(token, 0);
        assertEq(lender.collateralFactors(token), 0, "factor should be reset to 0 (default)");
    }

    function testCollateralFactorReverts() public {
        // Factor > 100% should revert
        vm.expectRevert(BurveLender.InvalidCollateralFactor.selector);
        lender.setCollateralFactor(tokens[0], 1e18 + 1);

        // Non-owner should revert
        vm.prank(alice);
        vm.expectRevert();
        lender.setCollateralFactor(tokens[0], 50e16);
    }

    function testCollateralFactorReducesBorrowingPower() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 100_000e18);

        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // Get baseline values
        uint256 rawCol = lender.collateralValueUSD(positionId);
        uint256 adjCol = lender.adjustedCollateralValueUSD(positionId);
        assertEq(rawCol, adjCol, "no factor set: raw == adjusted");

        // Set tokens[1] to 50% factor
        lender.setCollateralFactor(tokens[1], 50e16);

        uint256 adjColAfter = lender.adjustedCollateralValueUSD(positionId);
        assertLt(adjColAfter, rawCol, "adjusted should be less after factor reduction");

        // Max borrowable should also decrease
        uint256 maxBorrow = lender.maxBorrowable(positionId, borrowToken);
        uint256 maxBorrowRaw = (rawCol * 80) / 100; // 80% LTV on raw
        assertLt(maxBorrow, maxBorrowRaw, "max borrowable should be reduced");
    }

    function testCollateralFactorAffectsLTVCheck() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 100_000e18);

        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // Borrow 50% of raw collateral value (should work without factors)
        uint256 rawCol = lender.collateralValueUSD(positionId);
        uint256 borrowAmount = rawCol / 2;
        lender.borrow(positionId, borrowToken, borrowAmount);

        // Now set both tokens to 50% factor — this makes adjusted collateral = raw / 2
        // Debt is at 50% of raw, but now 100% of adjusted, which exceeds 80% LTV
        lender.setCollateralFactor(tokens[0], 50e16);
        lender.setCollateralFactor(tokens[1], 50e16);

        // Health factor should drop below 1
        uint256 hf = lender.healthFactor(positionId);
        assertLt(hf, 1e18, "position should be unhealthy after factor reduction");
    }

    function testGetTokenMargin() public {
        // Default: factor=100%, effective LTV = 80%
        (uint256 eLTV, uint256 factor) = lender.getTokenMargin(tokens[0]);
        assertEq(factor, 1e18, "default factor should be 1e18");
        assertEq(eLTV, 80e16, "default effective LTV should be 80%");

        // Set factor to 75%: effective LTV = 75% * 80% = 60%
        lender.setCollateralFactor(tokens[0], 75e16);
        (eLTV, factor) = lender.getTokenMargin(tokens[0]);
        assertEq(factor, 75e16, "factor should be 75%");
        assertEq(eLTV, 60e16, "effective LTV should be 60%");
    }

    function testGetPositionBreakdown() public {
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // Set token[0] to 90%, token[1] to 50%
        lender.setCollateralFactor(tokens[0], 90e16);
        lender.setCollateralFactor(tokens[1], 50e16);

        (
            address[] memory toks,
            uint256[16] memory rawValues,
            uint256[16] memory adjValues,
            uint256 totalRaw,
            uint256 totalAdj
        ) = lender.getPositionBreakdown(positionId);

        assertEq(toks.length, 3, "should have 3 tokens");
        assertGt(totalRaw, 0, "total raw should be > 0");
        assertLt(totalAdj, totalRaw, "adjusted should be < raw with reduced factors");

        // Verify individual adjustments
        uint256 expectedAdj0 = (rawValues[0] * 90) / 100;
        uint256 expectedAdj1 = (rawValues[1] * 50) / 100;
        assertApproxEqAbs(adjValues[0], expectedAdj0, 1, "token0 adjusted should match 90% factor");
        assertApproxEqAbs(adjValues[1], expectedAdj1, 1, "token1 adjusted should match 50% factor");
    }

    function testMaxBorrowableCapsByPoolLiquidity() public {
        address borrowToken = tokens[0];

        // Seed pool with only 10 tokens
        MockERC20(borrowToken).mint(alice, 10e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 10e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 10e18);

        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        uint256 maxBorrow = lender.maxBorrowable(positionId, borrowToken);
        // Pool only has 10 tokens, so max borrowable should be capped
        assertLe(maxBorrow, 10e18, "max borrowable should be capped by pool liquidity");
    }

    function testZeroCollateralFactorMeansDefault() public {
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // Factor = 0 (default) should behave as 100%
        uint256 rawCol = lender.collateralValueUSD(positionId);
        uint256 adjCol = lender.adjustedCollateralValueUSD(positionId);
        assertEq(rawCol, adjCol, "zero factor should equal raw collateral value");

        // Set factor then reset to 0
        lender.setCollateralFactor(tokens[0], 50e16);
        uint256 adjReduced = lender.adjustedCollateralValueUSD(positionId);
        assertLt(adjReduced, rawCol, "50% factor should reduce");

        lender.setCollateralFactor(tokens[0], 0);
        uint256 adjReset = lender.adjustedCollateralValueUSD(positionId);
        assertEq(adjReset, rawCol, "reset to 0 should restore full value");
    }
}
