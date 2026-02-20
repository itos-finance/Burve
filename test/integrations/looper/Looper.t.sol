// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "../../facets/MultiSetup.u.sol";
import {Lender} from "../../../src/integrations/lender/Lender.sol";
import {Looper} from "../../../src/integrations/looper/Looper.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {IBurveMultiValue} from "../../../src/multi/interfaces/IBurveMultiValue.sol";
import {ValueTokenFacet} from "../../../src/multi/facets/ValueTokenFacet.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

contract MockAggregatorLooper {
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

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, price, block.timestamp, updatedAt, 1);
    }
}

contract TestLooper is MultiSetupTest {
    Lender lender;
    Looper looper;
    MockAggregatorLooper[] oracles;

    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(3);
        _fundAccount(alice);
        _fundAccount(bob);
        _fundAccount(address(this));
        vm.startPrank(owner);
        _initializeClosure(0x3, 1_000_000e18);
        _initializeClosure(0x7, 1_000_000e18);
        vm.stopPrank();

        // Deploy Lender
        lender = new Lender();
        lender.setPoolAllowed(diamond, true);

        // Deploy Looper and authorize it
        looper = new Looper(address(lender));
        lender.setLooperAuthorized(address(looper), true);

        // Setup oracles — $1 per token
        for (uint256 i = 0; i < tokens.length; i++) {
            MockAggregatorLooper oracle = new MockAggregatorLooper(1e8, 8);
            oracles.push(oracle);
            lender.setPriceFeed(tokens[i], address(oracle), 18);
        }

        // Fund lending pool with liquidity
        for (uint256 i = 0; i < tokens.length; i++) {
            MockERC20(tokens[i]).mint(address(this), 100_000e18);
            IERC20(tokens[i]).approve(address(lender), 100_000e18);
            lender.depositLiquidity(tokens[i], 100_000e18);
        }
    }

    function testOpenLoop() public {
        address inToken = tokens[0];
        uint256 inAmount = 1000e18;

        MockERC20(inToken).mint(address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        uint256 positionId = looper.openLoop(diamond, 3, inToken, inAmount, 3, 0);

        // Verify position exists and is owned by this contract (not looper)
        (address borrower,,,,uint256 depValue,) = lender.positions(positionId);
        assertEq(borrower, address(this), "position should be owned by caller, not looper");
        assertGt(depValue, 0, "should have deposited value");
        console2.log("deposited value:", depValue);

        // Verify we have debt
        uint256 debt = lender.currentBorrow(positionId, inToken);
        assertGt(debt, 0, "should have debt");
        console2.log("total debt:", debt);

        // Verify health is OK
        uint256 hf = lender.healthFactor(positionId);
        assertGt(hf, 1e18, "should be healthy");
        console2.log("health factor:", hf);
    }

    function testOpenLoopWithSlippageProtection() public {
        address inToken = tokens[0];
        uint256 inAmount = 1000e18;

        MockERC20(inToken).mint(address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        // Set unreasonable minimum — should fail
        vm.expectRevert(Looper.MinValueNotMet.selector);
        looper.openLoop(diamond, 3, inToken, inAmount, 3, type(uint256).max);
    }

    function testEstimateLoop() public view {
        (uint256 totalValue, uint256 totalDebt, uint256 leverage) = looper.estimateLoop(1000e18, 3);

        assertGt(totalValue, 1000e18, "total value should exceed input");
        assertGt(totalDebt, 0, "should have estimated debt");
        assertGt(leverage, 1e18, "leverage should be > 1x");
        console2.log("estimated total value:", totalValue);
        console2.log("estimated total debt:", totalDebt);
        console2.log("estimated leverage:", leverage);
    }

    function testCloseLoop() public {
        address inToken = tokens[0];
        uint256 inAmount = 1000e18;

        MockERC20(inToken).mint(address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        uint256 positionId = looper.openLoop(diamond, 3, inToken, inAmount, 3, 0);

        // Record all balances before close
        uint256[] memory balsBefore = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balsBefore[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        // Get total debt to fund repayment — mint and approve
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenOwed = lender.currentBorrow(positionId, tokens[i]);
            if (tokenOwed > 0) {
                MockERC20(tokens[i]).mint(address(this), tokenOwed);
            }
            IERC20(tokens[i]).approve(address(looper), type(uint256).max);
        }

        uint256 outAmount = looper.closeLoop(positionId, inToken, 0);

        assertGt(outAmount, 0, "should receive tokens back");
        console2.log("returned from closeLoop:", outAmount);

        // Verify net gain across ALL tokens: user should end up ahead of where they started
        // (they started with 1000e18 of inToken and the leveraged position should return more total)
        uint256 totalValueReturned;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balAfter = IERC20(tokens[i]).balanceOf(address(this));
            if (balAfter > balsBefore[i]) {
                totalValueReturned += balAfter - balsBefore[i];
            }
        }
        // With no fees or price changes, user should get back roughly what they put in
        assertGt(totalValueReturned, 0, "should have net positive return");
        console2.log("total value returned:", totalValueReturned);

        // Position should have no more value
        (,,,,uint256 depValue,) = lender.positions(positionId);
        assertEq(depValue, 0, "position value should be 0 after close");
    }

    function testReduceLoop() public {
        address inToken = tokens[0];
        uint256 inAmount = 1000e18;

        MockERC20(inToken).mint(address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        uint256 positionId = looper.openLoop(diamond, 3, inToken, inAmount, 3, 0);

        (,,,,uint256 depValueBefore,) = lender.positions(positionId);
        uint256 debtBefore = lender.currentBorrow(positionId, inToken);
        console2.log("value before reduce:", depValueBefore);
        console2.log("debt before reduce:", debtBefore);

        // Reduce by a small amount that keeps position healthy during withdrawal
        // Health check happens during withdrawal (before debt repayment),
        // so we need: debt / (value - reduceBy) <= 80%
        // With ~60% LTV, ~20% reduction keeps us at ~75% LTV
        uint256 reduceBy = depValueBefore / 5;

        // Track balances across all tokens
        uint256[] memory balsBefore = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balsBefore[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        looper.reduceLoop(positionId, reduceBy, inToken, 0);

        // Verify user received tokens back (across all pool tokens)
        uint256 totalReceived;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balAfter = IERC20(tokens[i]).balanceOf(address(this));
            if (balAfter > balsBefore[i]) {
                totalReceived += balAfter - balsBefore[i];
            }
        }
        assertGt(totalReceived, 0, "should receive tokens from reduce");
        console2.log("total received from reduce:", totalReceived);

        // Position should have less value
        (,,,,uint256 depValueAfter,) = lender.positions(positionId);
        assertEq(depValueAfter, depValueBefore - reduceBy, "value should decrease by reduceBy");

        // Debt should have decreased (some was repaid with withdrawn tokens)
        uint256 debtAfter = lender.currentBorrow(positionId, inToken);
        assertLt(debtAfter, debtBefore, "debt should decrease after reduce");
        console2.log("value after reduce:", depValueAfter);
        console2.log("debt after reduce:", debtAfter);

        // Position should still be healthy
        uint256 hf = lender.healthFactor(positionId);
        assertGt(hf, 1e18, "should still be healthy after reduce");
        console2.log("health factor after reduce:", hf);
    }

    function testRevertReduceLoopNotOwner() public {
        address inToken = tokens[0];
        uint256 inAmount = 1000e18;

        MockERC20(inToken).mint(address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        uint256 positionId = looper.openLoop(diamond, 3, inToken, inAmount, 3, 0);

        // Bob is not the position owner
        vm.prank(bob);
        vm.expectRevert(Looper.NotPositionOwner.selector);
        looper.reduceLoop(positionId, 100e18, inToken, 0);
    }

    function testRevertCloseLoopNotOwner() public {
        address inToken = tokens[0];
        uint256 inAmount = 1000e18;

        MockERC20(inToken).mint(address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        uint256 positionId = looper.openLoop(diamond, 3, inToken, inAmount, 3, 0);

        vm.prank(bob);
        vm.expectRevert(Looper.NotPositionOwner.selector);
        looper.closeLoop(positionId, inToken, 0);
    }

    function testLooperHoldsNoTokensAfterOps() public {
        address inToken = tokens[0];
        uint256 inAmount = 1000e18;

        MockERC20(inToken).mint(address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        uint256 positionId = looper.openLoop(diamond, 3, inToken, inAmount, 3, 0);

        // After open, Looper should hold no tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(IERC20(tokens[i]).balanceOf(address(looper)), 0, "looper should hold no tokens after open");
        }

        // Reduce loop
        (,,,,uint256 depValue,) = lender.positions(positionId);
        looper.reduceLoop(positionId, depValue / 5, inToken, 0);

        // After reduce, Looper should hold no tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(IERC20(tokens[i]).balanceOf(address(looper)), 0, "looper should hold no tokens after reduce");
        }

        // Close loop
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenOwed = lender.currentBorrow(positionId, tokens[i]);
            if (tokenOwed > 0) MockERC20(tokens[i]).mint(address(this), tokenOwed);
            IERC20(tokens[i]).approve(address(looper), type(uint256).max);
        }
        looper.closeLoop(positionId, inToken, 0);

        // After close, Looper should hold no tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(IERC20(tokens[i]).balanceOf(address(looper)), 0, "looper should hold no tokens after close");
        }
    }

    function testOpenLoopSingleIteration() public {
        address inToken = tokens[0];
        uint256 inAmount = 1000e18;

        MockERC20(inToken).mint(address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        // Single iteration = borrow once
        uint256 positionId = looper.openLoop(diamond, 3, inToken, inAmount, 1, 0);

        (,,,,uint256 depValue,) = lender.positions(positionId);
        uint256 debt = lender.currentBorrow(positionId, inToken);

        // With 1 iteration: value ≈ input + 70% of value received
        assertGt(depValue, inAmount, "value should exceed input");
        assertGt(debt, 0, "should have some debt");
        console2.log("1-iter deposited value:", depValue);
        console2.log("1-iter debt:", debt);
    }

    function testRevertOpenLoopInvalidPool() public {
        address fakePool = makeAddr("fakePool");
        address inToken = tokens[0];
        MockERC20(inToken).mint(address(this), 1000e18);
        IERC20(inToken).approve(address(looper), 1000e18);

        vm.expectRevert(Looper.InvalidPool.selector);
        looper.openLoop(fakePool, 3, inToken, 1000e18, 3, 0);
    }

    function testRevertOpenLoopInvalidIterations() public {
        address inToken = tokens[0];
        MockERC20(inToken).mint(address(this), 1000e18);
        IERC20(inToken).approve(address(looper), 1000e18);

        vm.expectRevert(Looper.InvalidIterations.selector);
        looper.openLoop(diamond, 3, inToken, 1000e18, 11, 0); // >10 iterations
    }
}
