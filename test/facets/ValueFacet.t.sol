// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "./MultiSetup.u.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";

contract ValueFacetTest is MultiSetupTest {
    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(4);
        _initializeClosure(0xF, 100e18); // 1,2,3,4
        _initializeClosure(0xF, 100e18); // 2,3,4
        _initializeClosure(0xF, 100e18); // 1,2,4
        _initializeClosure(0xF, 100e18); // 1,3,4
        _initializeClosure(0x7, 100e18); // 1,2,3
        _initializeClosure(0xc, 100); // 3,4
        _initializeClosure(0xa, 100); // 2,4
        _initializeClosure(0x6, 100); // 2,3
        _initializeClosure(0x5, 100); // 1,3
        _initializeClosure(0x3, 100e18); // 1,2
        _initializeClosure(0x9, 100); // 1,4
        _initializeClosure(0x8, 100); // 4
        _initializeClosure(0x4, 100); // 3
        _initializeClosure(0x2, 100); // 2
        _initializeClosure(0x1, 100); // 1
        _fundAccount(alice);
        _fundAccount(bob);
        vm.stopPrank();
    }
    /// Test each method of add and remove.
    /// Test add with an irrelevant vertex.
    /// Test that a single value add can't raise by too much. Same with token add.
    /// Test that a single value remove can't lower by too much. Same with token remove.
    /// Test that add and remove is reversible.
    /// Test that a add token and add value single are symmetric.
    //  test that add token and remove token are symmetric.
    /// Test that add n* value split among n tokens is the same as m*value split among m tokens.
    /// Test you can't remove more than you put in.
    /// Test deposits earn value when as we collect fees, but no bgt without bgt value.
    /// Test deposits grow with vault growth.
    /// Test deposits earn bgt as we collect fees with bgt value.
    /// Test query matches value without fees, then with fees and bgt earned.
    /// Test after removing, there are no more fees earned. Test that with query then an add and remove. As in fee claims remain unchanged.
    /// Test fees in singles.
}
