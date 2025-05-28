// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

/// Test interactions with various vault scenarios.

import {MultiSetupTest} from "../facets/MultiSetup.u.sol";
import {console2 as console} from "forge-std/console2.sol";
import {VertexImpl} from "../../src/multi/vertex/Vertex.sol";
import {VertexId} from "../../src/multi/vertex/Id.sol";
import {VaultType} from "../../src/multi/vertex/VaultProxy.sol";
import {MockERC4626WithdrawlLimited} from "../mocks/MockERC4626.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract VaultMultiTest is MultiSetupTest {
    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(4);
        _installBGTExchanger();
        _fundAccount(alice);
        _fundAccount(bob);
        // Its annoying we have to fund first.
        _fundAccount(address(this));
        _fundAccount(owner);
        // So we have to redo the prank.
        vm.startPrank(owner);
        _initializeClosure(0xF, 100e18); // 1,2,3,4
        _initializeClosure(0x3, 100e18); // 1,2
        vm.stopPrank();
    }

    function testWithdrawLimits() public {
        vm.startPrank(owner);
        // Create a vault with a withdraw limit.
        MockERC4626WithdrawlLimited vault = new MockERC4626WithdrawlLimited(
            token0,
            "Test Vault",
            "TVLT",
            1e18
        );
        address vw = address(vault);
        address v0 = address(vaults[0]);
        vaultFacet.addVault(tokens[0], address(vault), VaultType.E4626);
        skip(5 days + 1);
        vaultFacet.acceptVault(tokens[0]);
        vaultFacet.transferBalance(v0, vw, 0x3, 100e18);
        vaultFacet.transferBalance(v0, vw, 0xF, 100e18);

        // As a backup its not an issue.
        valueFacet.addValueSingle(owner, 0x3, 2e18, 0, tokens[0], 0);
        valueFacet.removeValueSingle(owner, 0x3, 2e18, 0, tokens[0], 0);

        // But once we make it the active vault.
        vaultFacet.hotSwap(tokens[0]);
        // We can still deposit into it.
        valueFacet.addValueSingle(owner, 0x3, 5e18, 0, tokens[0], 0);
        // But we can't withdraw more than the limit.
        VertexId vid = VertexId.wrap(1 << 8); // VertexId for token0
        vm.expectRevert(
            abi.encodeWithSelector(
                VertexImpl.WithdrawLimited.selector,
                vid,
                2007094546280063563
            )
        );
        valueFacet.removeValueSingle(owner, 0x3, 2e18, 0, tokens[0], 0);
        // We can withdraw up to the limit. A little less value to
        valueFacet.removeSingleForValue(owner, 0x3, tokens[0], 1e18, 0, 0);
        // Someone can swap in.
        swapFacet.swap(owner, tokens[0], tokens[1], 10e18, 0, 0x3);
        // But can't swap out more than the limit.
        vm.expectRevert(
            abi.encodeWithSelector(
                VertexImpl.WithdrawLimited.selector,
                vid,
                10246160703694265782
            )
        );
        swapFacet.swap(owner, tokens[1], tokens[0], 10e18, 0, 0x3);
        // This is fine.
        swapFacet.swap(owner, tokens[1], tokens[0], 9e17, 0, 0x3);

        // Once we add a balance to the backup vault though, we can withdraw.
        vaultFacet.transferBalance(vw, v0, 0x3, 1e18);
        // We can withdraw past the limit.
        valueFacet.removeSingleForValue(owner, 0x3, tokens[0], 2e18, 0, 0);

        // But if we remove the vault.
        vaultFacet.removeVault(address(vaults[0]));
        // We can no longer withdraw past the limit.
        vm.expectRevert(
            abi.encodeWithSelector(
                VertexImpl.WithdrawLimited.selector,
                vid,
                2033158300660175021
            )
        );
        valueFacet.removeValueSingle(owner, 0x3, 2e18, 0, tokens[0], 0);
    }

    // TODO: test with bgt exchanger once the rounding bug is fixed.
}
