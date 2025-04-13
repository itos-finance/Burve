// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {SearchParams} from "../../src/multi/Value.sol";
import {Simplex, SimplexLib} from "../../src/multi/Simplex.sol";
import {Store} from "../../src/multi/Store.sol";

contract SimplexTest is Test {
    // -- earnings tests ----

    function testProtocolFees() public {
        uint256[MAX_TOKENS] memory protocolEarnings = SimplexLib
            .protocolEarnings();
        for (uint256 i = 0; i < MAX_TOKENS; i++) {
            assertEq(protocolEarnings[i], 0);
        }

        SimplexLib.protocolTake(0, 10e8);
        SimplexLib.protocolTake(1, 5e8);
        SimplexLib.protocolTake(2, 20e8);
        SimplexLib.protocolTake(3, 15e8);
        SimplexLib.protocolTake(4, 25e8);

        protocolEarnings = SimplexLib.protocolEarnings();
        assertEq(protocolEarnings[0], 10e8);
        assertEq(protocolEarnings[1], 5e8);
        assertEq(protocolEarnings[2], 20e8);
        assertEq(protocolEarnings[3], 15e8);
        assertEq(protocolEarnings[4], 25e8);

        for (uint256 i = 5; i < MAX_TOKENS; i++) {
            assertEq(protocolEarnings[i], 0);
        }
    }

    function testProtocolTake() public {
        SimplexLib.protocolTake(0, 10e8);
        SimplexLib.protocolTake(2, 5e8);

        Simplex storage simplex = Store.simplex();
        assertEq(simplex.protocolEarnings[0], 10e8);
        assertEq(simplex.protocolEarnings[1], 0);
        assertEq(simplex.protocolEarnings[2], 5e8);
    }

    function testProtocolGive() public {
        Simplex storage simplex = Store.simplex();

        uint256 amount = SimplexLib.protocolGive(0);
        assertEq(amount, 0);
        assertEq(simplex.protocolEarnings[0], 0);

        SimplexLib.protocolTake(1, 10e8);

        amount = SimplexLib.protocolGive(1);
        assertEq(amount, 10e8);
        assertEq(simplex.protocolEarnings[1], 0);
    }

    // -- adjustor tests ----

    function testGetAdjustorDefault() public {
        assertEq(SimplexLib.getAdjustor(), address(0x0));
    }

    function testGetAdjustorInit() public {
        address adjustor = makeAddr("initAdjustor");
        SimplexLib.init(adjustor);
        assertEq(SimplexLib.getAdjustor(), adjustor);
    }

    function testSetAdjustor() public {
        address adjustor = makeAddr("setAdjustor");
        SimplexLib.setAdjustor(adjustor);
        assertEq(SimplexLib.getAdjustor(), adjustor);
    }

    // -- searchParam tests ----

    function testGetSearchParamsDefault() public {
        SimplexLib.init(address(0x0));

        SearchParams memory sp = SimplexLib.getSearchParams();
        assertEq(sp.maxIter, 5);
        assertEq(sp.deMinimusX128, 100);
        assertEq(sp.targetSlippageX128, 1e12);
    }
}
