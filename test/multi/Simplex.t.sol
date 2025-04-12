// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {SearchParams} from "../../src/multi/Value.sol";
import {Simplex, SimplexLib} from "../../src/multi/Simplex.sol";

contract SimplexTest is Test {
    // -- searchParam tests ----

    function testGetSearchParamsDefault() public {
        SimplexLib.init(address(0x0));

        SearchParams memory sp = SimplexLib.getSearchParams();
        assertEq(sp.maxIter, 5);
        assertEq(sp.lookBack, 3);
        assertEq(sp.deMinimusX128, 1e6);
    }

    function testSetSearchParams() public {
        SearchParams memory sp = SearchParams(10, 5, 1e4);
        SimplexLib.setSearchParams(sp);

        SearchParams memory sp2 = SimplexLib.getSearchParams();
        assertEq(sp2.maxIter, sp.maxIter);
        assertEq(sp2.lookBack, sp.lookBack);
        assertEq(sp2.deMinimusX128, sp.deMinimusX128);
    }
}
