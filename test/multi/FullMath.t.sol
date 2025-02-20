// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {FullMath} from "../../src/FullMath.sol";

// TODO once we have a mock Erc4626
contract FullMathTest is Test {
    function setUp() public {}

    function testMulDivX256() public {
        {
            uint256 half = FullMath.mulDivX256(1000, 2000);
            uint256 half2 = FullMath.mulDivX256(123412341234, 246824682468);
            assertEq(half, half2);
            assertEq(half, 1 << 255);
        }

        {
            // With remainders rounding down.
            uint256 third = FullMath.mulDivX256(1112, 3333);
            uint256 third2 = FullMath.mulDivX256(1111111112, 3333333333);
            uint256 third3 = FullMath.mulDivX256(1111, 3333);
            assertGt(third, third2);
            assertGt(third2, third3);
        }
    }
}
