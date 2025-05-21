// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {VertexId, VertexLib} from "../../src/multi/vertex/Id.sol";
import {Vertex, VertexImpl} from "../../src/multi/vertex/Vertex.sol";
import {TokenRegistry, TokenRegLib} from "../../src/multi/Token.sol";
import {VaultType, VaultProxy, VaultLib} from "../../src/multi/vertex/VaultProxy.sol";
import {ClosureId} from "../../src/multi/closure/Id.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Store} from "../../src/multi/Store.sol";
import {SimplexLib} from "../../src/multi/Simplex.sol";
import {IBGTExchanger, BGTExchanger} from "../../src/integrations/BGTExchange/BGTExchanger.sol";

contract VertexIdTest is Test {
    function testExactId() public pure {
        assertEq(VertexId.unwrap(VertexLib.newId(0)), 1 << 8);
        assertEq(VertexId.unwrap(VertexLib.minId()), 1 << 8);
        assertEq(VertexId.unwrap(VertexLib.newId(1)), (1 << 9) + 1);
        assertEq(VertexId.unwrap(VertexLib.newId(2)), (1 << 10) + 2);
    }

    function testInc() public pure {
        assertEq(
            VertexId.unwrap(VertexLib.newId(5).inc()),
            VertexId.unwrap(VertexLib.newId(6))
        );
    }
}

contract VertexTest is Test {
    MockERC20 token;
    MockERC4626 vault;

    function setUp() public {
        token = new MockERC20("test", "TEST", 18);
        token.mint(address(this), 1e20);
        TokenRegLib.register(address(token));
        vault = new MockERC4626(ERC20(token), "Vault", "VAULT");
    }

    function testTrimBalance() public {
        VertexId vid = VertexLib.newId(0);
        Vertex storage v = Store.load().vertices[vid];
        ClosureId cid = ClosureId.wrap(0x1);
        v.init(vid, address(token), address(vault), VaultType.E4626);
        vm.expectEmit();
        emit VertexImpl.InsufficientBalance(vid, cid, 1e6, 0);
        v.trimBalance(cid, 1e6, 100, 50);

        // But if we add some tokens to the vault, then it's fine.
        VaultProxy memory vProxy = VaultLib.getProxy(vid);
        vProxy.deposit(cid, 4e6);
        vProxy.commit();
        // Now if we trim, we get a bunch.
        (uint256 regValShares, uint256 bgtResidual, uint256 unspent) = v
            .trimBalance(cid, 1e6, 150, 50);
        assertEq(regValShares, 2e6 * 100, "r"); // 100 for the reserve share resolution.
        // No exchange yet.
        assertEq(bgtResidual, 0, "b");
        assertEq(unspent, 1e8, "u"); // all unspent, * 100 for the reserve share resolution.

        // With Bgt exchange
        MockERC20 ibgt = new MockERC20("TestBGT", "iBGT", 18);
        IBGTExchanger bgtEx = new BGTExchanger(address(ibgt));
        ibgt.mint(address(this), 1e30);
        ibgt.approve(address(bgtEx), type(uint256).max);
        bgtEx.fund(1e30);
        bgtEx.addExchanger(address(this));
        bgtEx.setRate(address(token), 1 << 128);
        SimplexLib.setBGTExchanger(address(bgtEx));

        vProxy = VaultLib.getProxy(vid);
        vProxy.deposit(cid, 3e6);
        vProxy.commit();
        // Now a trim retains the 1e6 from before for the target, and the 3e6 is all rewards
        // and gets exchanged.
        (regValShares, bgtResidual, unspent) = v.trimBalance(cid, 1e6, 150, 50);
        assertEq(regValShares, 2e6 * 100, "r1"); // 100 for the reserve share resolution.
        // No exchange yet.
        assertEq(bgtResidual, 1e6, "b1"); // no 100 since its a real balance that gets exchanged.
        assertEq(unspent, 0, "u1"); // no unspent shares
    }
}
