// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {LiqFacet} from "../../src/multi/facets/LiqFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {LockFacet} from "../../src/multi/facets/LockFacet.sol";
import {MultiSetupTest} from "./MultiSetup.u.sol";

contract LockFacetTest is MultiSetupTest {
    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(3);
        _fundAccount(alice);
        vm.stopPrank();
    }

    /// Make sure only those authorized can lock.
    function testLockers() public {
        vm.expectRevert();
        vm.prank(alice);
        lockFacet.lock(address(token0));

        vm.prank(owner);
        lockFacet.lock(address(token0));

        vm.prank(owner);
        lockFacet.addLocker(alice);

        // Now it should work.
        vm.prank(alice);
        lockFacet.lock(address(token0));

        vm.prank(owner);
        lockFacet.removeLocker(alice);

        // And again it doesn't.
        vm.expectRevert();
        vm.prank(alice);
        lockFacet.lock(address(token0));

        // But the owner still can
        vm.prank(owner);
        lockFacet.lock(address(token0));
    }

    /// Make sure only those authorized can lock.
    function testUnlockers() public {
        vm.expectRevert();
        vm.prank(alice);
        lockFacet.unlock(address(token0));

        vm.prank(owner);
        lockFacet.unlock(address(token0));

        vm.prank(owner);
        lockFacet.addUnlocker(alice);

        // Now it should work.
        vm.prank(alice);
        lockFacet.unlock(address(token0));

        vm.prank(owner);
        lockFacet.removeUnlocker(alice);

        // And again it doesn't.
        vm.expectRevert();
        vm.prank(alice);
        lockFacet.unlock(address(token0));

        // But the owner still can
        vm.prank(owner);
        lockFacet.unlock(address(token0));
    }

    /// Test attempts to interact with liquidity when a vertex is locked.
    function testLockedLiq() public {
        uint128[] memory amounts = new uint128[](3);
        uint16 cid2 = 0x0003;
        uint16 cid3 = 0x0007;

        // Alice can originally add liquidity.
        amounts[0] = 1e18;
        amounts[1] = 1e18;
        amounts[2] = 1e18;
        vm.prank(alice);
        uint256 shares = liqFacet.addLiq(alice, cid3, amounts);

        vm.prank(owner);
        lockFacet.lock(address(token2));
        // But once token2 is locked she can't add more.
        vm.expectRevert(
            abi.encodeWithSelector(
                LiqFacet.VertexLockedInCID.selector,
                uint16(0x4)
            )
        );
        vm.prank(alice);
        liqFacet.addLiq(alice, cid3, amounts);
    }

    /// Test attempts to swap when a vertex is locked.
    function testLockedSwap() public {}
}
