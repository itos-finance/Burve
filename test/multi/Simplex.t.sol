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
        assertEq(sp.deMinimusX128, 100);
        assertEq(sp.targetSlippageX128, 1e12);
    }
}
