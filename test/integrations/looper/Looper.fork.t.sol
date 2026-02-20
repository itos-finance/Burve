// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BurveForkableTest} from "../Fork.u.sol";
import {Lender} from "../../../src/integrations/lender/Lender.sol";
import {Looper} from "../../../src/integrations/looper/Looper.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {IBurveMultiValue} from "../../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "../../../src/multi/facets/ValueTokenFacet.sol";

/// @notice Mock Chainlink aggregator for fork looper tests.
contract ForkLooperMockAggregator {
    int256 public price;
    uint256 public updatedAt;

    constructor(int256 _price) {
        price = _price;
        updatedAt = block.timestamp;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, price, block.timestamp, updatedAt, 1);
    }
}

contract TestLooperFork is BurveForkableTest {
    Lender lender;
    Looper looper;
    ForkLooperMockAggregator[] oracles;

    address constant MOCK_ROUTER = address(0xDEAD);

    function postSetup() internal override {
        if (!forking) return;

        lender = new Lender(MOCK_ROUTER);
        lender.setPoolAllowed(diamond, true);
        looper = new Looper(address(lender));

        // Setup mock oracles for first 3 tokens at $1.00
        for (uint256 i = 0; i < tokens.length && i < 3; i++) {
            ForkLooperMockAggregator oracle = new ForkLooperMockAggregator(1e8);
            oracles.push(oracle);
            lender.setPriceFeed(tokens[i], address(oracle), 18);
        }
    }

    /// @dev Seed lending pools with liquidity for borrowing.
    function _seedLendingPools(uint256 amount) internal {
        address lp = makeAddr("lp");
        for (uint256 i = 0; i < tokens.length && i < 3; i++) {
            deal(tokens[i], lp, amount);
            vm.startPrank(lp);
            IERC20(tokens[i]).approve(address(lender), amount);
            lender.depositLiquidity(tokens[i], amount);
            vm.stopPrank();
        }
    }

    // ============================================================
    //  Test: Open a leveraged loop on live diamond
    // ============================================================

    function testForkOpenLoop() public forkOnly {
        _seedLendingPools(100_000e18);

        address inToken = tokens[0];
        uint16 closureId = 3;
        uint256 inAmount = 1e15;

        deal(inToken, address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        uint256 positionId = looper.openLoop(diamond, closureId, inToken, inAmount, 3);

        (, address pool, uint16 cid,, uint256 depValue,) = lender.positions(positionId);
        assertEq(pool, diamond, "pool should be diamond");
        assertEq(cid, closureId, "closure should match");
        assertGt(depValue, 0, "should have deposited value");

        uint256 owed = lender.currentBorrow(positionId, inToken);
        assertGt(owed, 0, "should have debt from looping");

        uint256 hf = lender.healthFactor(positionId);
        assertGt(hf, 1e18, "position should be healthy");

        console2.log("fork looper: deposited value", depValue);
        console2.log("fork looper: total debt", owed);
        console2.log("fork looper: health factor", hf);
    }

    // ============================================================
    //  Test: Open loop with single iteration
    // ============================================================

    function testForkOpenLoopSingleIteration() public forkOnly {
        _seedLendingPools(100_000e18);

        address inToken = tokens[0];
        uint16 closureId = 3;
        uint256 inAmount = 1e15;

        deal(inToken, address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        uint256 positionId = looper.openLoop(diamond, closureId, inToken, inAmount, 1);

        (,,,, uint256 depValue,) = lender.positions(positionId);
        assertGt(depValue, 0, "should have deposited value");

        uint256 hf = lender.healthFactor(positionId);
        assertGt(hf, 1e18, "position should be healthy");

        console2.log("fork looper single iter: value", depValue);
        console2.log("fork looper single iter: hf", hf);
    }
}
