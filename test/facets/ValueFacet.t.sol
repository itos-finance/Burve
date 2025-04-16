// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "./MultiSetup.u.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";

contract ValueFacetTest is MultiSetupTest {
    /// Test that a single value add can't raise by too much. Same with token add.
    /// Test that a single value remove can't lower by too much. Same with token remove.
    /// Test that add and remove is reversible.
    /// Test that a add token and add value single are symmetric.
    //  test that add token and remove token are symmetric.
    /// Test that add n* value split among n tokens is the same as m*value split among m tokens.
    /// Test deposits earn value when as we collect fees, but no bgt without bgt value.
    /// Test deposits grow with vault growth.
    /// Test deposits earn bgt as we collect fees with bgt value.
    /// Test query matches value without fees, then with fees and bgt earned.
    /// Test after removing, there are no more fees earned. Test that with query then an add and remove. As in fee claims remain unchanged.
    /// Test fees in singles.
}
