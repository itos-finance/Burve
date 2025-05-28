// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "./MultiSetup.u.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IBurveMultiSwap} from "../../src/multi/interfaces/IBurveMultiSwap.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {ClosureImpl} from "../../src/multi/closure/Closure.sol";
import {VertexLib} from "../../src/multi/vertex/Id.sol";
import {ValueLib} from "../../src/multi/Value.sol";
import {ClosureId} from "../../src/multi/closure/Id.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {FullMath} from "../../src/FullMath.sol";
import {MAX_TOKENS} from "../../src/multi/Token.sol";

contract SwapFacetTest is MultiSetupTest {
    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(3);
        _initializeClosure(0x7, 100e18);
        _initializeClosure(0x3, 100e18);
        _fundAccount(alice);
        _fundAccount(bob);
        vm.stopPrank();
    }

    function testExactInputSwap() public {
        uint256 swapAmount = 1e18;
        uint256 beforeBalance0 = token0.balanceOf(alice);
        uint256 beforeBalance1 = token1.balanceOf(alice);

        vm.startPrank(alice);
        (uint256 inAmount, uint256 outAmount) = swapFacet.swap(
            alice, // recipient
            tokens[0], // tokenIn
            tokens[1], // tokenOut
            int256(swapAmount), // positive for exact input
            0, // no price limit{}
            0x3
        );

        assertEq(inAmount, swapAmount);

        // Verify token0 was taken
        assertEq(
            token0.balanceOf(alice),
            beforeBalance0 - inAmount,
            "Incorrect token0 balance after swap"
        );

        // Verify some token1 was received
        assertEq(
            token1.balanceOf(alice),
            beforeBalance1 + outAmount,
            "Should have received token1"
        );

        vm.stopPrank();
    }

    /// Similar to testing a regular oversized swap, but with multiple tokens.
    function testOversizedSwapIn() public {
        vm.startPrank(alice);

        // The first large swap is okay.
        swapFacet.swap(alice, tokens[0], tokens[1], 80e18, 0, 0x7);
        // But now the rest will be too large.
        vm.expectRevert(
            abi.encodeWithSelector(
                ClosureImpl.InsufficientVertexValue.selector,
                0x7,
                VertexLib.newId(1),
                8651246616634028732446094679936943476977673066481106321175,
                25376990075459817614217767333894578481464406779661016949153
            )
        );
        swapFacet.swap(alice, tokens[2], tokens[1], 80e18, 0, 0x7);
        vm.stopPrank();
    }

    function testExactOutputSwap() public {
        uint256 swapAmount = 80e18; // 80% of the pool.
        uint256 beforeBalance0 = token0.balanceOf(alice);
        uint256 beforeBalance1 = token1.balanceOf(alice);

        vm.startPrank(alice);
        (uint256 inAmount, uint256 outAmount) = swapFacet.swap(
            alice, // recipient
            tokens[0], // tokenIn
            tokens[1], // tokenOut
            -int256(swapAmount), // negative for exact out
            type(uint256).max, // no price limit
            0x3
        );
        vm.stopPrank();

        assertEq(outAmount, swapAmount);

        // Verify token0 was taken
        assertEq(
            token0.balanceOf(alice),
            beforeBalance0 - inAmount,
            "Incorrect token0 balance after swap"
        );

        // Verify some token1 was received
        assertEq(
            token1.balanceOf(alice),
            beforeBalance1 + outAmount,
            "Should have received token1"
        );
    }

    function testOversizedSwapOut() public {
        vm.startPrank(alice);

        // Simply request too much.
        vm.expectRevert(
            abi.encodeWithSelector(
                ClosureImpl.InsufficientVertexValue.selector,
                0x7,
                VertexLib.newId(1),
                100e18,
                120e18
            )
        );
        swapFacet.swap(alice, tokens[0], tokens[1], -120e18, 0, 0x7);
        vm.stopPrank();
    }

    function testSwapWithPriceLimit() public {
        // We error if we receive less than expected.
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurveMultiSwap.SlippageSurpassed.selector,
                1e18,
                998185117967332123,
                true
            )
        );
        swapFacet.swap(bob, address(token1), address(token0), 1e18, 1e18, 0x3); // We can't possibly swap 1 to 1.
        // But of course no problem swapping for slightly less.
        swapFacet.swap(
            bob,
            address(token1),
            address(token0),
            1e18,
            .99e18,
            0x3
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurveMultiSwap.SlippageSurpassed.selector,
                2e18,
                2014618544250459525,
                false
            )
        );
        swapFacet.swap(bob, address(token1), address(token0), -2e18, 2e18, 0x3); // We can't possibly swap 1 to 1.
        // But of course no problem swapping for slightly less.
        swapFacet.swap(
            bob,
            address(token1),
            address(token0),
            -2e18,
            2.015e18,
            0x3
        );
        vm.stopPrank();
    }

    function testOversizedSwap() public {
        // Given the efficiency factor of 10, t / 11 is the minimum balance.
        vm.startPrank(alice);
        uint256 smallX = 8333333333333333333;
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueLib.XTooSmall.selector,
                smallX,
                smallX + 1
            )
        );
        swapFacet.swap(
            alice,
            tokens[0],
            tokens[1],
            -100e18 + int256(smallX),
            0,
            0x7
        );
        // And the opposite side is true as well. Even if we didn't fail there,
        // we would have failed on the other end because we would have had to deposit too much.
        uint256 stillTooSmall = 9e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                ClosureImpl.TokenBalanceOutOfBounds.selector,
                ClosureId.wrap(0x7),
                0,
                209041394335511982570,
                smallX + 1,
                200e18
            )
        );
        swapFacet.swap(
            alice,
            tokens[0],
            tokens[1],
            -100e18 + int256(stillTooSmall),
            0,
            0x7
        );

        vm.stopPrank();
    }

    // Test swap symmetry, swap back and forth gets the same. thing. And also
    // implies the exact in and exact out are symmetric.

    function testSequentialSwapsIncreasePriceImpact() public {
        uint256 swapAmount = 1e12;
        vm.startPrank(alice);
        uint256 outAmount = swapAmount;
        for (uint8 i = 0; i < 10; ++i) {
            (, uint256 newOutAmount) = swapFacet.swap(
                alice,
                tokens[0],
                tokens[1],
                int256(swapAmount),
                0,
                0x7
            );
            assertLt(newOutAmount, outAmount);
            outAmount = newOutAmount;
        }
        uint256 inAmount = 0;
        for (uint8 i = 0; i < 10; ++i) {
            (uint256 newInAmount, ) = swapFacet.swap(
                alice,
                tokens[1],
                tokens[0],
                -int256(swapAmount),
                0,
                0x7
            );
            assertGt(newInAmount, inAmount);
            inAmount = newInAmount;
        }
    }

    function testSwapRevertLowAmount() public {
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurveMultiSwap.BelowMinSwap.selector,
                1e8,
                16e8
            )
        );
        swapFacet.swap(bob, address(token0), address(token1), 1e8, 0, 0x3);
        vm.stopPrank();
    }

    function testSwapRevertInvalidTokenPair() public {
        MockERC20 invalidToken = new MockERC20("Invalid Token", "INVALID", 18);

        vm.startPrank(bob);
        vm.expectRevert(); // Should revert for invalid token pair
        swapFacet.swap(
            bob,
            address(invalidToken),
            address(token1),
            int256(1e18),
            0,
            0x3
        );

        // We'll try with a token that exists but not in the closure of interest.
        vm.expectRevert();
        swapFacet.swap(bob, tokens[2], tokens[0], int256(1e18), 0, 0x3);
        vm.stopPrank();
    }

    function testSwapToSelf() public {
        uint256 swapAmount = 10e18;

        vm.startPrank(bob);
        vm.expectRevert(); // Should revert when trying to swap a token for itself
        swapFacet.swap(
            bob,
            address(token0),
            address(token0),
            int256(swapAmount),
            0,
            0x3
        );
        vm.stopPrank();
    }

    /// Without fees, swaps should be reversible.
    function testSwapSymmetry() public {
        int256 swapAmount = 53e16;
        vm.startPrank(alice);
        (uint256 in7, uint256 out7) = swapFacet.swap(
            alice,
            tokens[0],
            tokens[1],
            swapAmount,
            0,
            0x7
        );
        (uint256 reverseOut7, uint256 reverseIn7) = swapFacet.swap(
            alice,
            tokens[1],
            tokens[0],
            -swapAmount,
            0,
            0x7
        );
        assertEq(in7, uint256(swapAmount));
        assertEq(reverseIn7, in7);
        assertApproxEqAbs(out7, reverseOut7, 1);
        (, uint256 testOut7) = swapFacet.swap(
            alice,
            tokens[0],
            tokens[1],
            swapAmount,
            0,
            0x7
        );
        assertEq(testOut7, out7);
    }

    function testSwapAndRemoveLiquidity() public {
        uint256 swapAmount = 10e18;
        uint128 depositAmount = 400e18; // 200 for each token, init was 100 for each token.
        uint256 init0 = token0.balanceOf(alice);
        uint256 init1 = token1.balanceOf(alice);

        // First add liquidity.
        vm.prank(alice);
        valueFacet.addValue(alice, 0x3, depositAmount, 0);

        // First swap
        vm.prank(bob);
        (uint256 inAmount, uint256 outAmount) = swapFacet.swap(
            bob,
            address(token0),
            address(token1),
            int256(swapAmount),
            0,
            0x3
        );

        // Then remove liquidity
        vm.prank(alice);
        valueFacet.removeValue(alice, 0x3, depositAmount, 0);

        uint256 valueRatioX128 = (uint256(depositAmount) << 128) /
            (depositAmount + 200e18);
        console.log(inAmount, outAmount, valueRatioX128);
        uint256 excess0 = token0.balanceOf(alice) - init0;
        // Allow for rounding on withdrawal.
        assertApproxEqAbs(
            excess0,
            FullMath.mulX128(valueRatioX128, inAmount, false),
            3
        );
        uint256 lesser1 = init1 - token1.balanceOf(alice);
        assertApproxEqAbs(
            lesser1,
            FullMath.mulX128(valueRatioX128, outAmount, false),
            3
        );
    }

    function testSwapWithDifferentLiq() public {
        int256 swapAmount = 3e16;
        // We setup two closures which should swap the same with the same target
        // and same token balances even if one has one more token.
        vm.startPrank(alice);
        (uint256 in3, uint256 out3) = swapFacet.swap(
            alice,
            tokens[0],
            tokens[1],
            swapAmount,
            0,
            0x3
        );
        (uint256 in7, uint256 out7) = swapFacet.swap(
            alice,
            tokens[0],
            tokens[1],
            swapAmount,
            0,
            0x7
        );
        assertEq(out3, out7, "0");

        // Now if we add more liq to 0x7, the swap gets tighter.
        valueFacet.addValue(alice, 0x7, 3 * 7e17, 0); // Not even adding a lot.
        (in3, out3) = swapFacet.swap(
            alice,
            tokens[0],
            tokens[1],
            swapAmount,
            0,
            0x3
        );
        (in7, out7) = swapFacet.swap(
            alice,
            tokens[0],
            tokens[1],
            swapAmount,
            0,
            0x7
        );
        assertGt(out7, out3, "1");

        // We can undo the swap.
        (, uint256 reverseIn3) = swapFacet.swap(
            alice,
            tokens[1],
            tokens[0],
            int256(out3),
            0,
            0x3
        );
        (, uint256 reverseIn7) = swapFacet.swap(
            alice,
            tokens[1],
            tokens[0],
            int256(out7),
            0,
            0x7
        );
        assertApproxEqAbs(reverseIn3, in3, 2);
        assertApproxEqAbs(reverseIn7, in7, 2);

        // If we add equal value now, the swap will be the same.
        valueFacet.addValue(alice, 0x3, 2 * 7e17, 0);
        (
            ,
            uint256 target3X128,
            uint256[MAX_TOKENS] memory balances3,
            ,

        ) = simplexFacet.getClosureValue(0x3);
        (
            ,
            uint256 target7X128,
            uint256[MAX_TOKENS] memory balances7,
            ,

        ) = simplexFacet.getClosureValue(0x7);
        assertEq(target3X128, target7X128, "2t");
        assertEq(balances3[0], balances7[0], "2b0");
        assertEq(balances3[1], balances7[1], "2b1");

        (in3, out3) = swapFacet.swap(
            alice,
            tokens[1],
            tokens[0],
            -swapAmount,
            0,
            0x3
        );
        (in7, out7) = swapFacet.swap(
            alice,
            tokens[1],
            tokens[0],
            -swapAmount,
            0,
            0x7
        );
        assertEq(in3, in7, "2");

        // If we add equivalent liquidity to just the two tokens of interest in 0x7,
        // we get roughly the same result.
        valueFacet.addValue(alice, 0x3, 88e18, 0);
        valueFacet.addValueSingle(alice, 0x7, 66e18, 0, tokens[0], 0);
        valueFacet.addValueSingle(alice, 0x7, 66e18, 0, tokens[1], 0);
        swapAmount = 3e19;
        (in3, out3) = swapFacet.swap(
            alice,
            tokens[1],
            tokens[0],
            swapAmount,
            0,
            0x3
        );
        (in7, out7) = swapFacet.swap(
            alice,
            tokens[1],
            tokens[0],
            swapAmount,
            0,
            0x7
        );

        (, target3X128, , , ) = simplexFacet.getClosureValue(0x3);
        (, target7X128, , , ) = simplexFacet.getClosureValue(0x7);
        assertEq(target3X128, target7X128, "3t");
        assertGt(in3, out7); // There is still slippage despite being above target, though less.
        assertGt(out7, out3);
        assertApproxEqRel(out3, out7, 5e15, "3");

        (, , balances3, , ) = simplexFacet.getClosureValue(0x3);
        (, , balances7, , ) = simplexFacet.getClosureValue(0x7);
        console.log(out3, out7);
        console.log(target3X128, target7X128);
        assertLt(balances3[0], balances7[0], "3b0");
        assertLt(balances3[1], balances7[1], "3b1");
        vm.stopPrank();
    }

    function testSwapWithFees() public {
        /// First make Alice half of the pool.
        vm.prank(alice);
        valueFacet.addValue(alice, 0x7, 300e18, 0);

        int256 swapAmount = -12e18;
        (uint256 simIn, uint256 simOut, ) = swapFacet.simSwap(
            tokens[2],
            tokens[1],
            swapAmount,
            0x7
        );
        vm.prank(owner);
        simplexFacet.setSimplexFees(1 << 126, 1 << 127); // 1/4, 1/2
        (uint256 simFeeIn, uint256 simFeeOut, ) = swapFacet.simSwap(
            tokens[2],
            tokens[1],
            swapAmount,
            0x7
        );
        assertGt(simFeeIn, simIn);
        assertEq(simFeeOut, simOut); // Fees come from the input.
        // Now the actual swap.
        vm.prank(alice);
        (uint256 actualIn, uint256 actualOut) = swapFacet.swap(
            alice,
            tokens[2],
            tokens[1],
            swapAmount,
            0,
            0x7
        );
        assertEq(actualOut, simOut);
        assertEq(actualIn, simFeeIn);

        // Now check the fees went to the right places.
        uint256 totalEarnings = actualIn - simIn;
        assertApproxEqAbs(totalEarnings, actualIn / 4, 2, "e0"); // The fees were indeed the right rate.
        // Half has gone to the protocol.
        vm.prank(owner);
        uint256 protocolAmount = simplexFacet.withdraw(tokens[2]);
        assertApproxEqAbs(protocolAmount, totalEarnings / 2, 2, "e1");
        // Half of the rest has gone to alice.
        (, , uint256[MAX_TOKENS] memory earnings, ) = valueFacet.queryValue(
            alice,
            0x7
        );
        assertApproxEqAbs(earnings[2], totalEarnings / 4, 2, "e2");
    }

    function testSimSwapIsTheSame() public {
        vm.startPrank(alice);
        // Add a bunch of random liquidity.
        valueFacet.addValueSingle(alice, 0x7, 220e18, 12e18, tokens[0], 0);
        valueFacet.addValueSingle(alice, 0x7, 331e18, 111e18, tokens[1], 0);
        valueFacet.addValueSingle(alice, 0x7, 555e18, 99e18, tokens[2], 0);

        // A sim swap here gives the same result as the real swap.
        int256 swapAmount = 1919e16;
        (uint256 simIn, uint256 simOut, ) = swapFacet.simSwap(
            tokens[2],
            tokens[0],
            swapAmount,
            0x7
        );
        (uint256 realIn, uint256 realOut) = swapFacet.swap(
            alice,
            tokens[2],
            tokens[0],
            swapAmount,
            0,
            0x7
        );
        assertEq(simIn, realIn);
        assertEq(simOut, realOut);
    }

    function testFeeChange() public {
        vm.prank(alice);
        (uint256 feeLess0, uint256 feeLess1, ) = swapFacet.simSwap(
            tokens[0],
            tokens[1],
            1e18,
            0x7
        );

        vm.prank(owner);
        simplexFacet.setSimplexFees(1 << 124, 0); // 1/16

        vm.prank(alice);
        (uint256 def0, uint256 def1, ) = swapFacet.simSwap(
            tokens[0],
            tokens[1],
            1e18,
            0x7
        );
        assertEq(def0, feeLess0);
        assertLt(def1, feeLess1);

        vm.prank(owner);
        // This doesn't affect the swap since its the wrong edge.
        simplexFacet.setEdgeFee(1, 2, 1 << 126); // 1/4

        vm.prank(alice);
        (uint256 test0, uint256 test1, ) = swapFacet.simSwap(
            tokens[0],
            tokens[1],
            1e18,
            0x7
        );

        assertEq(test0, def0);
        assertEq(test1, def1);

        vm.prank(owner);
        // Setting the correct edge changes things.
        simplexFacet.setEdgeFee(0, 1, 1 << 126); // 1/4
        // On both sides.
        vm.prank(alice);
        (uint256 inAmount, uint256 outAmount, ) = swapFacet.simSwap(
            tokens[0],
            tokens[1],
            1e18,
            0x7
        );
        assertEq(inAmount, def0);
        assertLt(outAmount, def1);
        vm.prank(alice);
        (test0, test1, ) = swapFacet.simSwap(tokens[0], tokens[1], -1e18, 0x7);
        assertGt(test0, FullMath.mulDiv(def0, 1e18, def1));
        assertEq(test1, 1e18);

        // Now a change to the default fee won't do anything.
        vm.prank(owner);
        simplexFacet.setSimplexFees(1 << 127, 0); // 1/2
        vm.prank(alice);
        (test0, test1, ) = swapFacet.simSwap(tokens[0], tokens[1], 1e18, 0x7);
        assertEq(test0, inAmount);
        assertEq(test1, outAmount);
    }
}
