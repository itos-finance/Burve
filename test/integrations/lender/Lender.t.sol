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

contract TestLender is MultiSetupTest {
    Lender lender;
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

        // Deploy Lender
        lender = new Lender(ROUTER);
        lender.setPoolAllowed(diamond, true);

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

    /// @dev Helper to deposit collateral into Lender.
    function _depositCollateral(
        uint16 closureId,
        uint128 depositValue
    ) internal returns (uint256 positionId, uint256 posValue) {
        posValue = _openPosition(closureId, depositValue);

        // Approve Lender to transfer value
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

        (uint256 totalDeposited,,,,uint256 totalShares) = lender.lendingPools(token);
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
        vm.expectRevert(Lender.ExceedsMaxLTV.selector);
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

        vm.prank(bob);
        vm.expectRevert(Lender.PositionHealthy.selector);
        lender.liquidate(positionId, txData);
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
        assertEq(PositionProxy(proxy).lender(), address(lender), "proxy lender should be Lender");
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
        vm.expectRevert(Lender.InvalidCollateralFactor.selector);
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

    // ============================================================
    //                     LIQUIDATION TESTS
    // ============================================================

    function testLiquidationAfterPriceDrop() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 100_000e18);

        // Deposit collateral and borrow near max LTV
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        uint256 maxBorrow = lender.maxBorrowable(positionId, borrowToken);
        // Borrow 60% of max. In a 2-token closure, removeValue returns ~50% per token.
        // Without a real router swap, the debt must be coverable by the borrowed token's
        // share of the removeValue proceeds alone (~500e18 of tokens[0]).
        uint256 borrowAmount = (maxBorrow * 60) / 100;
        lender.borrow(positionId, borrowToken, borrowAmount);

        // Position should be healthy
        uint256 hf = lender.healthFactor(positionId);
        assertGt(hf, 1e18, "should be healthy before price drop");

        // Drop only the NON-borrowed collateral token price aggressively.
        // Closure 3 = tokens[0]+tokens[1]. We borrow tokens[0], so drop tokens[1] to crash collateral.
        // At 60% max borrow (~$480 debt), collateral must drop below $480/0.85 = ~$565
        // tokens[0] stays at $500, so tokens[1] must drop below $65 → price to $0.05
        oracles[1].setPrice(0.05e8);

        // Position should now be unhealthy
        hf = lender.healthFactor(positionId);
        console2.log("health factor after price drop", hf);
        assertLt(hf, 1e18, "should be unhealthy after price drop");

        // Liquidate
        bytes[MAX_TOKENS] memory txData; // no swaps needed in mock

        vm.prank(bob);
        lender.liquidate(positionId, txData);

        // Position should be emptied
        (,,,,uint256 depValue,) = lender.positions(positionId);
        assertEq(depValue, 0, "deposited value should be 0 after liquidation");
    }

    // ============================================================
    //                     ADD COLLATERAL TESTS
    // ============================================================

    function testAddCollateral() public {
        uint16 closureId = 3;
        (uint256 positionId, uint256 posValue) = _depositCollateral(closureId, 500e18);

        // Open a second position to have value to add
        uint256 extraValue = _openPosition(closureId, 500e18);

        // Approve and add
        ValueTokenFacet(diamond).approve(address(lender), closureId, extraValue, 0);
        lender.addCollateral(positionId, extraValue, 0);

        (,,,,uint256 depValue,) = lender.positions(positionId);
        assertEq(depValue, posValue + extraValue, "deposited value should increase");
    }

    // ============================================================
    //                     REPAY MAX TESTS
    // ============================================================

    function testRepayMax() public {
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

        // Advance time to accrue interest
        vm.warp(block.timestamp + 30 days);

        uint256 owedNow = lender.currentBorrow(positionId, borrowToken);
        assertGt(owedNow, 100e18, "interest should have accrued");

        // Repay with max uint
        MockERC20(borrowToken).mint(address(this), 1000e18); // extra to cover interest
        IERC20(borrowToken).approve(address(lender), type(uint256).max);
        lender.repay(positionId, borrowToken, type(uint256).max);

        uint256 owedAfter = lender.currentBorrow(positionId, borrowToken);
        assertEq(owedAfter, 0, "debt should be 0 after max repay");
    }

    // ============================================================
    //                     ORACLE EDGE CASE TESTS
    // ============================================================

    function testOracleStalenessReverts() public {
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // Warp forward 2 hours so oracles become stale (MAX_STALENESS = 1 hour)
        vm.warp(block.timestamp + 2 hours);

        // Querying value should revert with StaleOracle
        vm.expectRevert();
        lender.collateralValueUSD(positionId);
    }

    function testOracleZeroPriceReverts() public {
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // Set price to 0
        oracles[0].setPrice(0);

        vm.expectRevert();
        lender.collateralValueUSD(positionId);
    }

    // ============================================================
    //                     WITHDRAWAL EDGE CASES
    // ============================================================

    function testWithdrawCollateralRevertsWhenBorrowedTooMuch() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 100_000e18);

        uint16 closureId = 3;
        (uint256 positionId, uint256 posValue) = _depositCollateral(closureId, 1000e18);

        // Borrow at ~75% LTV
        uint256 colUSD = lender.collateralValueUSD(positionId);
        uint256 borrowAmount = (colUSD * 75) / 100;
        lender.borrow(positionId, borrowToken, borrowAmount);

        // Try to withdraw most of the collateral — should fail
        vm.expectRevert(Lender.WithdrawalWouldLiquidate.selector);
        lender.withdrawCollateral(positionId, (posValue * 90) / 100, 0);
    }

    function testNotPositionOwnerReverts() public {
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // Alice tries to withdraw — should fail
        vm.prank(alice);
        vm.expectRevert(Lender.NotPositionOwner.selector);
        lender.withdrawCollateral(positionId, 100, 0);

        // Alice tries to borrow — should fail
        vm.prank(alice);
        vm.expectRevert(Lender.NotPositionOwner.selector);
        lender.borrow(positionId, tokens[0], 100);
    }

    // ============================================================
    //                     LP INTEREST EARNING TESTS
    // ============================================================

    function testLPEarnsInterest() public {
        address borrowToken = tokens[0];

        // Alice deposits liquidity
        MockERC20(borrowToken).mint(alice, 10_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 10_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 10_000e18);

        // Deposit collateral and borrow (stay within 80% LTV)
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);
        uint256 maxBorrow = lender.maxBorrowable(positionId, borrowToken);
        lender.borrow(positionId, borrowToken, maxBorrow / 2); // borrow at 40% LTV

        // Advance time
        vm.warp(block.timestamp + 365.25 days);

        // Repay borrow first to free liquidity
        uint256 owed = lender.currentBorrow(positionId, borrowToken);
        MockERC20(borrowToken).mint(address(this), owed);
        IERC20(borrowToken).approve(address(lender), owed);
        lender.repay(positionId, borrowToken, type(uint256).max);

        // Alice withdraws all — should get more than deposited due to interest
        uint256 aliceShares = lender.lpShares(borrowToken, alice);
        uint256 aliceBalBefore = IERC20(borrowToken).balanceOf(alice);
        vm.prank(alice);
        lender.withdrawLiquidity(borrowToken, aliceShares);

        uint256 aliceBalAfter = IERC20(borrowToken).balanceOf(alice);
        uint256 received = aliceBalAfter - aliceBalBefore;
        assertGt(received, 10_000e18, "LP should earn interest");
        console2.log("LP earned", received - 10_000e18);
    }

    // ============================================================
    //                     POOL WHITELIST TESTS
    // ============================================================

    function testPoolNotAllowedReverts() public {
        // Deploy a fresh lender without whitelisting the pool
        Lender freshLender = new Lender(ROUTER);
        // Don't call setPoolAllowed

        // Open position value
        uint256 posValue = _openPosition(3, 1000e18);
        ValueTokenFacet(diamond).approve(address(freshLender), 3, posValue, 0);

        vm.expectRevert(Lender.PoolNotAllowed.selector);
        freshLender.depositCollateral(diamond, 3, posValue, 0);
    }

    function testPoolWhitelistCanBeToggled() public {
        // Deposit works with whitelist
        uint256 posValue = _openPosition(3, 500e18);
        ValueTokenFacet(diamond).approve(address(lender), 3, posValue, 0);
        uint256 posId = lender.depositCollateral(diamond, 3, posValue, 0);
        (,,,,uint256 dep,) = lender.positions(posId);
        assertGt(dep, 0, "deposit should work with whitelist");

        // Revoke whitelist
        lender.setPoolAllowed(diamond, false);

        // New deposits should fail
        uint256 posValue2 = _openPosition(3, 500e18);
        ValueTokenFacet(diamond).approve(address(lender), 3, posValue2, 0);
        vm.expectRevert(Lender.PoolNotAllowed.selector);
        lender.depositCollateral(diamond, 3, posValue2, 0);

        // Re-enable
        lender.setPoolAllowed(diamond, true);
        lender.depositCollateral(diamond, 3, posValue2, 0);
    }

    // ============================================================
    //                     WITHDRAW ALL WITH DEBT TEST
    // ============================================================

    function testWithdrawAllCollateralWithDebtReverts() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 100_000e18);

        uint16 closureId = 3;
        (uint256 positionId, uint256 posValue) = _depositCollateral(closureId, 1000e18);

        // Borrow small amount
        lender.borrow(positionId, borrowToken, 10e18);

        // Try to withdraw ALL collateral — should fail with HasOutstandingDebt
        vm.expectRevert(Lender.HasOutstandingDebt.selector);
        lender.withdrawCollateral(positionId, posValue, 0);
    }

    // ============================================================
    //                     BORROW WITHOUT PRICE FEED TEST
    // ============================================================

    function testBorrowWithoutPriceFeedReverts() public {
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        // Create a token with no price feed
        address noPriceFeedToken = makeAddr("noPriceFeed");

        vm.expectRevert(Lender.NoPriceFeed.selector);
        lender.borrow(positionId, noPriceFeedToken, 100e18);
    }

    // ============================================================
    //                     LIQUIDATION SURPLUS DISTRIBUTION TEST
    // ============================================================

    function testLiquidationSurplusDistribution() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 100_000e18);

        // Deposit collateral and borrow conservatively
        uint16 closureId = 3;
        (uint256 positionId, ) = _depositCollateral(closureId, 1000e18);

        uint256 maxBorrow = lender.maxBorrowable(positionId, borrowToken);
        // Borrow 60% of max — high enough to become unhealthy on price drop,
        // but low enough that tokens[0] proceeds from removeValue cover the debt
        uint256 borrowAmount = (maxBorrow * 60) / 100;
        lender.borrow(positionId, borrowToken, borrowAmount);

        // Get borrower address before liquidation clears it
        (address borrower,,,,,) = lender.positions(positionId);

        // Aggressively drop non-borrowed token to trigger liquidation
        oracles[1].setPrice(0.05e8);

        uint256 hf = lender.healthFactor(positionId);
        assertLt(hf, 1e18, "should be unhealthy");

        // Record balances before liquidation
        uint256 bobBalBefore = IERC20(borrowToken).balanceOf(bob);
        uint256 borrowerBalBefore = IERC20(borrowToken).balanceOf(borrower);

        bytes[MAX_TOKENS] memory txData;
        vm.prank(bob);
        lender.liquidate(positionId, txData);

        // Verify liquidator received bonus (3% of surplus)
        uint256 bobBalAfter = IERC20(borrowToken).balanceOf(bob);
        assertGt(bobBalAfter, bobBalBefore, "liquidator should receive bonus");

        // Verify borrower received remainder (95% of surplus)
        uint256 borrowerBalAfter = IERC20(borrowToken).balanceOf(borrower);
        assertGt(borrowerBalAfter, borrowerBalBefore, "borrower should receive surplus");

        // Liquidator should get less than borrower (3% vs 95%)
        uint256 liquidatorGain = bobBalAfter - bobBalBefore;
        uint256 borrowerGain = borrowerBalAfter - borrowerBalBefore;
        assertGt(borrowerGain, liquidatorGain, "borrower share should exceed liquidator share");

        console2.log("liquidator bonus", liquidatorGain);
        console2.log("borrower surplus", borrowerGain);

        // Verify position is cleared
        (address borrowerAfter,,,,uint256 depValue,) = lender.positions(positionId);
        assertEq(depValue, 0, "deposited value should be 0");
        assertEq(borrowerAfter, address(0), "borrower should be cleared");
    }

    // ============================================================
    //                     MULTIPLE BORROWERS TEST
    // ============================================================

    function testMultiplePositionsIndependent() public {
        address borrowToken = tokens[0];

        // Seed lending pool
        MockERC20(borrowToken).mint(alice, 100_000e18);
        vm.prank(alice);
        IERC20(borrowToken).approve(address(lender), 100_000e18);
        vm.prank(alice);
        lender.depositLiquidity(borrowToken, 100_000e18);

        // Position 1: this contract
        uint16 closureId = 3;
        (uint256 pos1, ) = _depositCollateral(closureId, 1000e18);
        lender.borrow(pos1, borrowToken, 100e18);

        // Position 2: bob
        uint256 posValue2 = _openPosition(closureId, 1000e18);
        ValueTokenFacet(diamond).approve(address(bob), closureId, posValue2, 0);

        vm.startPrank(bob);
        ValueTokenFacet(diamond).approve(address(lender), closureId, posValue2, 0);
        vm.stopPrank();

        // Transfer value to bob so he can deposit
        ValueTokenFacet(diamond).transfer(bob, closureId, posValue2, 0);

        vm.startPrank(bob);
        ValueTokenFacet(diamond).approve(address(lender), closureId, posValue2, 0);
        uint256 pos2 = lender.depositCollateral(diamond, closureId, posValue2, 0);
        lender.borrow(pos2, borrowToken, 50e18);
        vm.stopPrank();

        // Verify positions are independent
        uint256 owed1 = lender.currentBorrow(pos1, borrowToken);
        uint256 owed2 = lender.currentBorrow(pos2, borrowToken);
        assertEq(owed1, 100e18, "pos1 debt should be 100");
        assertEq(owed2, 50e18, "pos2 debt should be 50");

        // Bob can't touch pos1
        vm.prank(bob);
        vm.expectRevert(Lender.NotPositionOwner.selector);
        lender.borrow(pos1, borrowToken, 1e18);
    }

    // ============================================================
    //                     SHARE INFLATION ATTACK TEST
    // ============================================================

    function testShareInflationMitigated() public {
        address token = tokens[0];

        // Attacker deposits 1 wei first, then donates a large amount to inflate share price
        MockERC20(token).mint(alice, 1 + 10_000e18);
        vm.startPrank(alice);
        IERC20(token).approve(address(lender), type(uint256).max);
        lender.depositLiquidity(token, 1); // Deposit 1 wei to get shares
        vm.stopPrank();

        // Attacker directly transfers tokens to inflate the pool
        // (In real attack, attacker would use a different mechanism to donate)
        // With virtual shares, this donation doesn't drastically affect the share price
        vm.prank(alice);
        IERC20(token).transfer(address(lender), 10_000e18);

        // Victim deposits a normal amount
        MockERC20(token).mint(bob, 1000e18);
        vm.startPrank(bob);
        IERC20(token).approve(address(lender), 1000e18);
        lender.depositLiquidity(token, 1000e18);
        vm.stopPrank();

        // Victim should receive non-zero shares
        uint256 bobShares = lender.lpShares(token, bob);
        assertGt(bobShares, 0, "victim should receive shares even after donation attack");

        // Victim should be able to withdraw a meaningful amount (not rounded to zero)
        vm.prank(bob);
        lender.withdrawLiquidity(token, bobShares);
        uint256 bobBal = IERC20(token).balanceOf(bob);
        // With virtual shares, bob shouldn't lose more than a tiny fraction
        assertGt(bobBal, 900e18, "victim should recover most of deposit with virtual shares");
    }

    // ============================================================
    //          BORROW RESTRICTED TO POOL TOKENS
    // ============================================================

    function testBorrowNonPoolTokenReverts() public {
        // Deposit collateral
        (uint256 positionId,) = _depositCollateral(0x3, 1000e18);

        // Create a non-pool token and set up a price feed + liquidity for it
        MockERC20 fakeToken = new MockERC20("FAKE", "FAKE", 18);
        MockAggregator fakeOracle = new MockAggregator(1e8, 8);
        lender.setPriceFeed(address(fakeToken), address(fakeOracle), 18);
        fakeToken.mint(address(this), 10_000e18);
        IERC20(address(fakeToken)).approve(address(lender), 10_000e18);
        lender.depositLiquidity(address(fakeToken), 10_000e18);

        // Attempt to borrow the non-pool token — should revert
        vm.expectRevert(Lender.NotPoolToken.selector);
        lender.borrow(positionId, address(fakeToken), 100e18);
    }

    // ============================================================
    //          PROTOCOL REVENUE WITHDRAWAL
    // ============================================================

    function testClaimProtocolRevenue() public {
        address token = tokens[0];

        // LP deposits
        MockERC20(token).mint(address(this), 10_000e18);
        IERC20(token).approve(address(lender), 10_000e18);
        lender.depositLiquidity(token, 10_000e18);

        // Open position and borrow a small amount (10% of max to avoid LTV issues after interest)
        (uint256 positionId,) = _depositCollateral(0x3, 1000e18);
        uint256 maxBorrow = lender.maxBorrowable(positionId, token);
        uint256 borrowAmt = maxBorrow / 10; // 10% of max — safe even with 1 year interest
        lender.borrow(positionId, token, borrowAmt);

        // Advance time for interest to accrue
        vm.warp(block.timestamp + 365 days);

        // Update oracle timestamps so they don't go stale
        for (uint256 i = 0; i < oracles.length; i++) {
            oracles[i].setPrice(1e8);
        }

        // Owner claims protocol revenue
        address treasury = address(0xBEEF);
        uint256 balBefore = IERC20(token).balanceOf(treasury);
        lender.claimProtocolRevenue(token, treasury);
        uint256 balAfter = IERC20(token).balanceOf(treasury);

        // Revenue should be > 0 (interest reserve cut)
        assertGt(balAfter - balBefore, 0, "protocol should receive revenue from interest reserves");
    }

    function testClaimProtocolRevenueOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        lender.claimProtocolRevenue(tokens[0], alice);
    }
}
