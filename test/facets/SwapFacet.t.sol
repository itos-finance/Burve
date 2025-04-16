// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {MultiSetupTest} from "./MultiSetup.u.sol";
import {console2 as console} from "forge-std/console2.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {ClosureImpl} from "../../src/multi/closure/Closure.sol";
import {ValueLib} from "../../src/multi/Value.sol";
import {ClosureId} from "../../src/multi/closure/Id.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {FullMath} from "../../src/FullMath.sol";

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
        vm.stopPrank();

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

    function testSwapWithPriceLimit() public {
        // We error if we receive less than expected.
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapFacet.SlippageSurpassed.selector,
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
                SwapFacet.SlippageSurpassed.selector,
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

    function testSwapRevertZeroAmount() public {
        vm.startPrank(bob);
        // If you swap nothing and get nothing, that's fine i guess.
        swapFacet.swap(bob, address(token0), address(token1), 0, 0, 0x3);
        // But if you swap something and get nothing, that doesn't seem desirable.
        vm.expectRevert(); // Should revert for zero amount out.
        swapFacet.swap(bob, address(token0), address(token1), 1, 0, 0x3);
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
            int256(1000e18),
            0,
            0x3
        );
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
        assertEq(excess0, FullMath.mulX128(valueRatioX128, inAmount, false));
        uint256 lesser1 = init1 - token1.balanceOf(alice);
        assertEq(lesser1, FullMath.mulX128(valueRatioX128, outAmount, false));
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
        valueFacet.addValue(alice, 0x7, 7e17, 0); // Not even adding a lot.
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

        // If we add equal value now, the swap back will be the same.
        valueFacet.addValue(alice, 0x3, 7e17, 0);
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
        valueFacet.addValue(alice, 0x3, 88e22, 0);
        valueFacet.addValueSingle(alice, 0x7, 44e22, 0, tokens[0], 0);
        valueFacet.addValueSingle(alice, 0x7, 44e22, 0, tokens[1], 0);
        swapAmount = 3e21;
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
        assertEq(out3, out7, "3");
        vm.stopPrank();
    }

    function testSwapWithFees() public {
        assertTrue(false);
    }
}
