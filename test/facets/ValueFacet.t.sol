// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "./MultiSetup.u.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

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
        _fundAccount(address(this));
        vm.stopPrank();
    }

    function getBalances(
        address who
    ) public returns (uint256[4] memory balances) {
        for (uint8 i = 0; i < 4; ++i) {
            balances[i] = ERC20(tokens[i]).balanceOf(who);
        }
    }

    function diffBalances(
        uint256[4] memory a,
        uint256[4] memory b
    ) public returns (int256[4] memory diffs) {
        for (uint8 i = 0; i < 4; ++i) {
            diffs[i] = int256(a[i]) - int256(b[i]);
        }
    }

    function testAddRemoveValue() public {
        // Add and remove value will fund using multiple tokens and has no size limitations like the single methods do.
        uint256[4] memory initBalances = getBalances(address(this));
        valueFacet.addValue(alice, 0x9, 1e30, 5e29);
        (uint256 value, uint256 bgtValue, , ) = valueFacet.queryValue(
            alice,
            0x9
        );
        assertEq(value, 1e30);
        assertEq(bgtValue, 5e29);
        uint256[4] memory currentBalances = getBalances(address(this));
        int256[4] memory diffs = diffBalances(initBalances, currentBalances);
        assertEq(diffs[0], 5e29);
        assertEq(diffs[1], 0);
        assertEq(diffs[2], 0);
        assertEq(diffs[3], 5e29);

        // Of course we have no value to remove.
        vm.expectRevert();
        valueFacet.removeValue(alice, 0x9, 5e29, 1e29);
        // But alice does.
        initBalances = getBalances(alice);
        vm.startPrank(alice);
        valueFacet.removeValue(alice, 0x9, 5e29, 5e29);
        // But she can't remove more bgt value now even though she has more value.
        vm.expectRevert();
        valueFacet.removeValue(alice, 0x9, 5e29, 1);
        // She can only remove regular value.
        valueFacet.removeValue(alice, 0x9, 5e29, 0);
        // And now she's out.
        vm.expectRevert();
        valueFacet.removeValue(alice, 0x9, 1, 0);
        vm.stopPrank();
        currentBalances = getBalances(alice);
        diffs = diffBalances(currentBalances, initBalances);
        assertEq(diffs[0], 5e29);
        assertEq(diffs[1], 0);
        assertEq(diffs[2], 0);
        assertEq(diffs[3], 5e29);
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
