// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "../../facets/MultiSetup.u.sol";
import {BurveLender} from "../../../src/integrations/lender/BurveLender.sol";
import {BurveLooper} from "../../../src/integrations/looper/BurveLooper.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {IBurveMultiValue} from "../../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "../../../src/multi/facets/ValueTokenFacet.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {FullMath} from "../../../src/FullMath.sol";

/// @notice Mock Chainlink aggregator for looper testing.
contract MockAggregatorLooper {
    int256 public price;
    uint256 public updatedAt;

    constructor(int256 _price) {
        price = _price;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price) external {
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

contract TestBurveLooper is MultiSetupTest {
    BurveLender lender;
    BurveLooper looper;
    MockAggregatorLooper[] oracles;
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

        lender = new BurveLender(ROUTER);
        looper = new BurveLooper(address(lender));

        // Setup oracles
        for (uint256 i = 0; i < tokens.length; i++) {
            MockAggregatorLooper oracle = new MockAggregatorLooper(1e8);
            oracles.push(oracle);
            lender.setPriceFeed(tokens[i], address(oracle), 18);
        }
    }

    /// @dev Seed lending pools with liquidity for borrowing.
    function _seedLendingPools(uint256 amount) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            MockERC20(tokens[i]).mint(alice, amount);
            vm.startPrank(alice);
            IERC20(tokens[i]).approve(address(lender), amount);
            lender.depositLiquidity(tokens[i], amount);
            vm.stopPrank();
        }
    }

    // ============================================================
    //                     ESTIMATE TESTS
    // ============================================================

    function testEstimateLoop() public view {
        (uint256 totalValue, uint256 totalDebt, uint256 leverage) = looper.estimateLoop(
            diamond,
            3, // closureId
            tokens[0],
            1000e18,
            5
        );

        console2.log("estimated total value", totalValue);
        console2.log("estimated total debt", totalDebt);
        console2.log("estimated leverage (1e18=1x)", leverage);

        assertGt(totalValue, 1000e18, "total value should exceed initial deposit");
        assertGt(totalDebt, 0, "should have debt");
        assertGt(leverage, 1e18, "leverage should be > 1x");
        assertLe(leverage, 5e18, "leverage should be <= 5x (max at 80% LTV)");
    }

    function testEstimateLoopVaryingIterations() public view {
        uint256 prevLeverage;
        for (uint8 iters = 1; iters <= 10; iters++) {
            (,, uint256 leverage) = looper.estimateLoop(
                diamond,
                3,
                tokens[0],
                1000e18,
                iters
            );
            assertGe(leverage, prevLeverage, "leverage should increase with iterations");
            prevLeverage = leverage;
        }
    }

    // ============================================================
    //                     OPEN LOOP TESTS
    // ============================================================

    function testOpenLoop() public {
        _seedLendingPools(100_000e18);

        address inToken = tokens[0];
        uint16 closureId = 3;
        uint256 inAmount = 1000e18;

        MockERC20(inToken).mint(address(this), inAmount);
        IERC20(inToken).approve(address(looper), inAmount);

        uint256 positionId = looper.openLoop(
            diamond,
            closureId,
            inToken,
            inAmount,
            3 // 3 iterations
        );

        console2.log("position ID", positionId);

        // Verify position exists in BurveLender
        (, address pool, uint16 cid,, uint256 depValue,) = lender.positions(positionId);
        assertEq(pool, diamond, "pool should be diamond");
        assertEq(cid, closureId, "closure should match");
        assertGt(depValue, 0, "should have deposited value");
        console2.log("deposited value", depValue);

        // Check debt exists
        uint256 owed = lender.currentBorrow(positionId, inToken);
        console2.log("total debt", owed);
        assertGt(owed, 0, "should have debt from looping");

        // Check health factor
        uint256 hf = lender.healthFactor(positionId);
        console2.log("health factor", hf);
        assertGt(hf, 1e18, "position should be healthy");
    }

    function testOpenLoopRejectsZeroAmount() public {
        vm.expectRevert(BurveLooper.ZeroAmount.selector);
        looper.openLoop(diamond, 3, tokens[0], 0, 3);
    }

    function testOpenLoopRejectsExcessiveIterations() public {
        MockERC20(tokens[0]).mint(address(this), 1000e18);
        IERC20(tokens[0]).approve(address(looper), 1000e18);

        vm.expectRevert(BurveLooper.InvalidIterations.selector);
        looper.openLoop(diamond, 3, tokens[0], 1000e18, 11);
    }

    function testOpenLoopRejectsInvalidToken() public {
        address fakeToken = makeAddr("fake");
        vm.expectRevert(BurveLooper.InvalidToken.selector);
        looper.openLoop(diamond, 3, fakeToken, 1000e18, 3);
    }
}
