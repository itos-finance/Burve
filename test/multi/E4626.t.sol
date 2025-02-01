// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Store} from "../../src/multi/Store.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {VaultTemp} from "../../src/multi/VaultProxy.sol";
import {VaultE4626, VaultE4626Impl} from "../../src/multi/E4626.sol";
import {ClosureId} from "../../src/multi/Closure.sol";

// TODO once we have a mock Erc4626
contract E4626Test is Test {
    IERC20 public token;
    IERC4626 public e4626;
    VaultE4626 public vault;

    function setUp() public {
        token = IERC20(address(new MockERC20("test", "TEST", 18)));
        MockERC20(address(token)).mint(address(this), 1 << 128);
        e4626 = IERC4626(
            address(new MockERC4626(ERC20(address(token)), "vault", "V"))
        );
        token.approve(address(e4626), 1 << 128);
        vault.init(address(token), address(e4626));
    }

    // Test an empty fetch and commit
    function testEmpty() public {
        ClosureId cid = ClosureId.wrap(1);
        VaultTemp memory temp;
        vault.fetch(temp);
        console.log("before balance");
        console.log(temp.vars[0]);
        console.log("indexed");
        assertEq(vault.balance(temp, cid, false), 0);
        console.log("after balance");
        // Empty commit.
        vault.commit(temp);
    }

    function testDeposit() public {
        ClosureId cid = ClosureId.wrap(1);
        VaultTemp memory temp;
        vault.fetch(temp);
        vault.deposit(temp, cid, 1e10);
        vault.commit(temp);
        assertEq(vault.balance(temp, cid, false), 1e10);
    }

    // We fail if we try to deposit and withdraw in the same operation.
    function testOverlap() public {
        ClosureId cid = ClosureId.wrap(1);
        VaultTemp memory temp;
        vault.fetch(temp);
        vault.deposit(temp, cid, 1e10);
        // errors when trying to withdraw too much.
        vm.expectRevert();
        vault.withdraw(temp, cid, 1e15);
        // This works though.
        vault.withdraw(temp, cid, 1e5);
        // This faults with overlap.
        vm.expectRevert(
            VaultE4626Impl.OverlappingOperations.selector,
            address(e4626)
        );
        vault.commit(temp);
    }

    function testWithdraw() public {
        ClosureId cid = ClosureId.wrap(1);
        {
            VaultTemp memory temp;
            vault.fetch(temp);
            vault.deposit(temp, cid, 1e10);
            vault.commit(temp);
            assertEq(vault.balance(temp, cid, false), 1e10);
        }
        // Now withdraw
        {
            VaultTemp memory temp;
            vault.fetch(temp);
            vault.withdraw(temp, cid, 1e10);
            vault.commit(temp);
            assertEq(vault.balance(temp, cid, false), 0);
        }
    }
}
