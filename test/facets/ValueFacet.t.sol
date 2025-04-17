// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "./MultiSetup.u.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {AssetBookImpl} from "../../src/multi/Asset.sol";

contract ValueFacetTest is MultiSetupTest {
    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(4);
        _fundAccount(alice);
        _fundAccount(bob);
        // Its annoying we have to fund first.
        _fundAccount(address(this));
        _fundAccount(owner);
        // So we have to redo the prank.
        vm.startPrank(owner);
        _initializeClosure(0xF, 100e18); // 1,2,3,4
        _initializeClosure(0xF, 100e18); // 2,3,4
        _initializeClosure(0xF, 100e18); // 1,2,4
        _initializeClosure(0xF, 100e18); // 1,3,4
        _initializeClosure(0x7, 100e18); // 1,2,3
        _initializeClosure(0xc, 1e12); // 3,4
        _initializeClosure(0xa, 1e12); // 2,4
        _initializeClosure(0x6, 1e12); // 2,3
        _initializeClosure(0x5, 1e12); // 1,3
        _initializeClosure(0x3, 100e18); // 1,2
        _initializeClosure(0x9, 1e18); // 1,4
        _initializeClosure(0x8, 1e12); // 4
        _initializeClosure(0x4, 1e12); // 3
        _initializeClosure(0x2, 1e12); // 2
        _initializeClosure(0x1, 1e12); // 1
        vm.stopPrank();
    }

    function getBalances(
        address who
    ) public view returns (uint256[4] memory balances) {
        for (uint8 i = 0; i < 4; ++i) {
            balances[i] = ERC20(tokens[i]).balanceOf(who);
        }
    }

    function diffBalances(
        uint256[4] memory a,
        uint256[4] memory b
    ) public pure returns (int256[4] memory diffs) {
        for (uint8 i = 0; i < 4; ++i) {
            diffs[i] = int256(a[i]) - int256(b[i]);
        }
    }

    function testAddRemoveValue() public {
        // Add and remove value will fund using multiple tokens and has no size limitations like the single methods do.
        uint256[4] memory initBalances = getBalances(address(this));
        valueFacet.addValue(alice, 0x9, 1e28, 5e27);
        (uint256 value, uint256 bgtValue, , ) = valueFacet.queryValue(
            alice,
            0x9
        );
        assertEq(value, 1e28);
        assertEq(bgtValue, 5e27);
        uint256[4] memory currentBalances = getBalances(address(this));
        int256[4] memory diffs = diffBalances(initBalances, currentBalances);
        assertEq(diffs[0], 5e27);
        assertEq(diffs[1], 0);
        assertEq(diffs[2], 0);
        assertEq(diffs[3], 5e27);

        // Of course we have no value to remove.
        vm.expectRevert();
        valueFacet.removeValue(alice, 0x9, 5e27, 1e27);
        // But alice does.
        initBalances = getBalances(alice);
        vm.startPrank(alice);
        valueFacet.removeValue(alice, 0x9, 5e27, 5e27);
        // But she can't remove more bgt value now even though she has more value.
        vm.expectRevert();
        valueFacet.removeValue(alice, 0x9, 5e27, 1);
        // She can only remove regular value.
        valueFacet.removeValue(alice, 0x9, 5e27, 0);
        // And now she's out.
        vm.expectRevert();
        valueFacet.removeValue(alice, 0x9, 1, 0);
        vm.stopPrank();
        currentBalances = getBalances(alice);
        diffs = diffBalances(currentBalances, initBalances);
        assertApproxEqAbs(diffs[0], 5e27, 2, "0");
        assertEq(diffs[1], 0);
        assertEq(diffs[2], 0);
        assertApproxEqAbs(diffs[3], 5e27, 2, "3");
    }

    function testAddRemoveValueSingle() public {
        uint256[4] memory initBalances = getBalances(address(this));
        // This is too much to put into one token.
        vm.expectRevert();
        valueFacet.addValueSingle(alice, 0x9, 1e28, 5e27, tokens[0], 0);
        // So we add less.
        // Of course bgt can't be larger.
        vm.expectRevert();
        valueFacet.addValueSingle(alice, 0x9, 1e19, 5e19, tokens[0], 0);
        // Finally okay.
        uint256 requiredBalance = valueFacet.addValueSingle(
            alice,
            0x9,
            1e19,
            5e18,
            tokens[0],
            0
        );
        assertGt(requiredBalance, 1e19);
        assertApproxEqRel(requiredBalance, 1e19, 1e17);
        // We can't add irrelevant tokens though.
        vm.expectRevert();
        valueFacet.addValueSingle(alice, 0x9, 1e19, 5e18, tokens[1], 0);

        (uint256 value, uint256 bgtValue, , ) = valueFacet.queryValue(
            alice,
            0x9
        );
        assertEq(value, 1e19);
        assertEq(bgtValue, 5e18);
        uint256[4] memory currentBalances = getBalances(address(this));
        int256[4] memory diffs = diffBalances(initBalances, currentBalances);
        assertEq(uint256(diffs[0]), requiredBalance);
        assertEq(diffs[1], 0);
        assertEq(diffs[2], 0);
        assertEq(diffs[3], 0);

        // We have no value to remove.
        vm.expectRevert(AssetBookImpl.InsufficientValue.selector);
        valueFacet.removeValueSingle(alice, 0x9, 5e26, 1e25, tokens[0], 0);
        // But alice does.
        initBalances = getBalances(alice);
        vm.startPrank(alice);
        // But she can't remove from something other 0, there aren't enough tokens.
        vm.expectRevert();
        valueFacet.removeValueSingle(alice, 0x9, 1e25, 1, tokens[3], 0);
        // Removing a small amount is fine.
        valueFacet.removeValueSingle(alice, 0x9, 1e6, 1, tokens[3], 0);
        // But token3 is so valuable now, so you won't get much back.
        vm.expectRevert();
        valueFacet.removeValueSingle(alice, 0x9, 1e6, 1, tokens[3], 9e5);
        // But she can't remove from an irrelevant token. even if its small.
        vm.expectRevert();
        valueFacet.removeValueSingle(alice, 0x9, 1e6, 1, tokens[1], 0);
        // token 0 is fine.
        valueFacet.removeValueSingle(alice, 0x9, 5e25, 5e25, tokens[0], 0);
        // But she can't remove more bgt value now even though she has more value.
        vm.expectRevert();
        valueFacet.removeValueSingle(alice, 0x9, 5e25, 1, tokens[0], 0);
        // She can only remove regular value.
        valueFacet.removeValueSingle(alice, 0x9, 5e25, 0, tokens[0], 0);
        // And now she's out.
        vm.expectRevert();
        valueFacet.removeValueSingle(alice, 0x9, 1, 0, tokens[0], 0);
        vm.stopPrank();
        currentBalances = getBalances(alice);
        diffs = diffBalances(currentBalances, initBalances);
        assertApproxEqAbs(diffs[0], 5e27, 2, "0");
        assertEq(diffs[1], 0);
        assertEq(diffs[2], 0);
        assertApproxEqAbs(diffs[3], 5e27, 2, "3");
    }

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
