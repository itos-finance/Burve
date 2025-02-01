// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Store} from "../../src/multi/Store.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {VaultTemp} from "../../src/multi/VaultProxy.sol";
import {VaultE4626} from "../../src/multi/E4626.sol";

// TODO once we have a mock Erc4626
contract E4626Test is Test {
    IERC20 public token;
    IERC4626 public e4626;
    VaultE4626 public vault;

    function setUp() public {
        token = IERC20(address(new MockERC20("test", "TEST")));
        e4626 = IERC4626(address(new MockERC4626()));
        vault.token =
    }
}
