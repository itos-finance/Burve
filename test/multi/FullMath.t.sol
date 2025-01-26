// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {FullMath} from "../../src/multi/FullMath.sol";

// TODO once we have a mock Erc4626
contract FullMathTest is Test {
    function setUp() public {}

    function testMulDivX256() public {
        uint256 half = FullMath.mulDivX256(1000, 2000);
        uint256 half2 = FullMath.mulDivX256(123412341234, 246824682468);
        assertEq(half, 1 << 255);
    }
}
