// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console, stdError} from "forge-std/Test.sol";

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import {Store} from "../../../src/multi/Store.sol";
import {VertexId, VertexLib} from "../../../src/multi/vertex/Id.sol";
import {VaultLib, VaultProxy} from "../../../src/multi/vertex/VaultProxy.sol";
import {VaultType} from "../../../src/multi/vertex/VaultPointer.sol";
import {Reserve, ReserveLib} from "../../../src/multi/vertex/Reserve.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockERC4626} from "../../mocks/MockERC4626.sol";

contract ReserveTest is Test {
    VertexId public vid;
    address public token;
    address public vault;

    function setUp() public {
        vid = VertexLib.newId(0);

        token = address(new MockERC20("token", "t", 18));
        vault = address(new MockERC4626(ERC20(address(token)), "vault", "v"));

        VaultLib.add(vid, token, vault, VaultType.E4626);
    }

    // -- deposit vid tests ----

    function testDeposit() public {
        deal(token, address(this), 100e18);

        Reserve storage reserve = Store.reserve();

        // initial deposit
        uint256 shares = ReserveLib.deposit(vid, 10e18);
        assertEq(shares, 10e18 * uint256(ReserveLib.SHARE_RESOLUTION));
        assertEq(reserve.shares[0], shares);

        // second deposit lower amount
        VaultProxy memory vProxy = VaultLib.getProxy(vid);
        uint256 shares2 = ReserveLib.deposit(vProxy, vid, 5e18);
        assertEq(shares2, 5e18 * uint256(ReserveLib.SHARE_RESOLUTION));
        assertEq(reserve.shares[0], shares + shares2);
        vProxy.commit();

        // third deposit greater amount
        uint256 shares3 = ReserveLib.deposit(vid, 15e18);
        assertEq(shares3, 15e18 * uint256(ReserveLib.SHARE_RESOLUTION));
        assertEq(reserve.shares[0], shares + shares2 + shares3);
    }

    // -- query tests ----

    function testQuery() public {
        deal(token, address(this), 100e18);

        // deposit
        uint256 shares = ReserveLib.deposit(vid, 100e18);
        assertEq(shares, 100e20);

        // query partial
        uint256 amount = ReserveLib.query(vid, 10e20);
        assertEq(amount, 10e18);

        // query full
        amount = ReserveLib.query(vid, 100e20);
        assertEq(amount, 100e18);

        // query zero
        amount = ReserveLib.query(vid, 0);
        assertEq(amount, 0);
    }

    function testQueryEmpty() public {
        uint256 amount = ReserveLib.query(vid, 10e20);
        assertEq(amount, 0);
    }

    function testQueryMoreThanShares() public {
        deal(token, address(this), 100e18);

        // deposit
        uint256 shares = ReserveLib.deposit(vid, 100e18);
        assertEq(shares, 100e20);

        uint256 amount = ReserveLib.query(vid, 200e20);
        assertEq(amount, 200e18);
    }

    // -- withdraw tests ----

    function testWithdraw() public {
        deal(token, address(this), 100e18);

        Reserve storage reserve = Store.reserve();

        // deposit
        uint256 shares = ReserveLib.deposit(vid, 100e18);
        assertEq(shares, 100e20);

        // withdraw partial
        uint256 amount = ReserveLib.withdraw(vid, 20e20);
        assertEq(amount, 20e18);
        assertEq(reserve.shares[0], 80e20);

        // withdraw half
        amount = ReserveLib.withdraw(vid, 40e20);
        assertEq(amount, 40e18);
        assertEq(reserve.shares[0], 40e20);

        // withdraw zero
        amount = ReserveLib.withdraw(vid, 0);
        assertEq(amount, 0);
        assertEq(reserve.shares[0], 40e20);

        // withdraw all
        amount = ReserveLib.withdraw(vid, 40e20);
        assertEq(amount, 40e18);
        assertEq(reserve.shares[0], 0);
    }

    function testWithdrawEmpty() public {
        uint256 amount = ReserveLib.withdraw(vid, 10e20);
        assertEq(amount, 0);
    }
}
