// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MultiSetupTest} from "./MultiSetup.u.sol";
import {ValueTokenFacet} from "../../src/multi/facets/ValueTokenFacet.sol";
import {Store} from "../../src/multi/Store.sol";
import {SimplexLib} from "../../src/multi/Simplex.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";

contract ValueTokenTest is MultiSetupTest {
    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(2);
        _initializeClosure(3); // Initialize closure with both tokens
        vm.stopPrank();

        _fundAccount(alice);
        _fundAccount(bob);
    }

    function test_ValueTokenNameAndSymbol() public view {
        // The name and symbol should be constructed from the simplex name and symbol
        // which are set to "N/A" during diamond initialization
        string memory expectedName = string.concat("brvValue", "N/A");
        string memory expectedSymbol = string.concat("val", "N/A");

        // We need to call the functions directly since the constructor isn't called
        assertEq(valueTokenFacet.name(), expectedName);
        assertEq(valueTokenFacet.symbol(), expectedSymbol);
    }

    function test_MintValue() public {
        uint256 value = 1000e18;
        uint256 bgtValue = 500e18;

        // First add some value to the closure for alice
        vm.startPrank(alice);
        valueFacet.addValue(alice, 3, uint128(value), uint128(bgtValue));
        vm.stopPrank();

        // Now mint value tokens
        vm.startPrank(alice);
        valueTokenFacet.mint(value, bgtValue, 3);
        vm.stopPrank();

        assertEq(valueTokenFacet.balanceOf(alice), value);
    }

    function test_MintValue_RevertWhenBgtValueExceedsValue() public {
        uint256 value = 1000e18;
        uint256 bgtValue = 1500e18; // BGT value exceeds total value

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueTokenFacet.InsufficientValueForBgt.selector,
                value,
                bgtValue
            )
        );
        valueTokenFacet.mint(value, bgtValue, 3);
        vm.stopPrank();
    }

    function test_BurnValue() public {
        uint256 value = 1000e18;
        uint256 bgtValue = 500e18;

        // First add some value to the closure for alice
        vm.startPrank(alice);
        valueFacet.addValue(alice, 3, uint128(value), uint128(bgtValue));
        vm.stopPrank();

        // First mint some tokens
        vm.startPrank(alice);
        valueTokenFacet.mint(value, bgtValue, 3);
        vm.stopPrank();

        // Then burn them
        vm.startPrank(alice);
        valueTokenFacet.burn(value, bgtValue, 3);
        vm.stopPrank();

        assertEq(valueTokenFacet.balanceOf(alice), 0);
    }

    function test_BurnValue_RevertWhenBgtValueExceedsValue() public {
        uint256 value = 1000e18;
        uint256 bgtValue = 1500e18; // BGT value exceeds total value

        // First add some value to the closure for alice
        vm.startPrank(alice);
        valueFacet.addValue(alice, 3, uint128(value), uint128(500e18));
        vm.stopPrank();

        // First mint some tokens
        vm.startPrank(alice);
        valueTokenFacet.mint(value, 500e18, 3);
        vm.stopPrank();

        // Try to burn with invalid BGT value
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueTokenFacet.InsufficientValueForBgt.selector,
                value,
                bgtValue
            )
        );
        valueTokenFacet.burn(value, bgtValue, 3);
        vm.stopPrank();
    }

    function test_BurnValue_RevertWhenInsufficientBalance() public {
        uint256 value = 1000e18;
        uint256 bgtValue = 500e18;

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                0,
                value
            )
        );
        valueTokenFacet.burn(value, bgtValue, 3);
        vm.stopPrank();
    }

    function test_TransferValue() public {
        uint256 value = 1000e18;
        uint256 bgtValue = 500e18;

        // First add some value to the closure for alice
        vm.startPrank(alice);
        valueFacet.addValue(alice, 3, uint128(value), uint128(bgtValue));
        vm.stopPrank();

        // Mint tokens to alice
        vm.startPrank(alice);
        valueTokenFacet.mint(value, bgtValue, 3);
        vm.stopPrank();

        // Transfer from alice to bob
        vm.startPrank(alice);
        valueTokenFacet.transfer(bob, value);
        vm.stopPrank();

        assertEq(valueTokenFacet.balanceOf(alice), 0);
        assertEq(valueTokenFacet.balanceOf(bob), value);
    }
}
