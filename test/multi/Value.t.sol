// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ValueLib, SearchParams} from "../../src/multi/Value.sol";

contract ValueTest is Test {
    /// When x is at target, it'll be equal to value no matter e or rounding.
    function testVwhenXatT() public pure {
        assertEq(
            10e18 << 128,
            ValueLib.v(10e18 << 128, 10 << 128, 10e18, true)
        );

        assertEq(
            10e18 << 128,
            ValueLib.v(10e18 << 128, 27 << 128, 10e18, false)
        );

        uint256 x = 12345e18;
        assertEq(x << 128, ValueLib.v(x << 128, 0, x, false));

        x = 8_888_888e18;
        assertEq(x << 128, ValueLib.v(x << 128, 1e6 << 128, x, true));
    }

    /// Test the v function at hard coded test cases.
    function testVHardCoded() public pure {}

    /// Test revert when we provide an x that is too small.
    function testNegativeV() public pure {}

    /// When v is at t, x will be equal to v no matter e or rounding.
    function testXwhenVatT() public pure {
        assertEq(
            10e18,
            ValueLib.x(10e18 << 128, 157 << 125, 10e18 << 128, true)
        );
        uint256 x = 181818e18;
        assertEq(x, ValueLib.x(x << 128, 1 << 125, x << 128, false));
        x = 5e12;
        assertEq(x, ValueLib.x(x << 128, 555 << 128, x << 128, false));
        x = 19e16;
        assertEq(x, ValueLib.x(x << 128, 47 << 128, x << 128, false));
        x = 12e6;
        assertEq(x, ValueLib.x(x << 128, 36 << 122, x << 128, false));
        x = 290e30;
        assertEq(x, ValueLib.x(x << 128, 15 << 127, x << 128, false));
    }

    /// Test x at some hard coded values.
    function testXHardCoded() public pure {}

    /// Test t when everything is in balance. It should equal the balances.
    function testTatEquilibrium() public pure {
        SearchParams memory params = SearchParams({
            maxIter: 5,
            lookBack: 3,
            deMinimusX128: 1e6
        });
        uint256[] memory esX128 = new uint256[](3);
        uint256[] memory xs = new uint256[](3);
        for (uint256 i = 0; i < 3; ++i) {
            esX128[i] = 10 << 128;
            xs[i] = 100e18;
        }
        // Let's try starting at the right place.
        assertEq(100e18 << 128, ValueLib.t(params, esX128, xs, 100e18 << 128));
        // And now we need to search from a little off.
        // TODO resolve.
        assertEq(100e18 << 128, ValueLib.t(params, esX128, xs, 110e18 << 128));
    }

    /// Test t at some hard coded test cases.
    function testTHardCoded() public pure {}

    /// Test hard coded test cases for dvdt
    function testDvdtHardCoded() public pure {}

    /// Test hard coded values for stepT
    function testStepT() public pure {}
}
