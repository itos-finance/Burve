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
import {ClosureId} from "../../src/multi/closure/Id.sol";

contract ValueTokenFacetTest is MultiSetupTest {
    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(2);
        _initializeClosure(3); // Initialize closure with both tokens
        _initializeClosure(1);
        vm.stopPrank();

        _fundAccount(alice);
        _fundAccount(bob);
    }

    function test_ValueTokenNameAndSymbol() public view {
        string memory expectedName = "brvValueToken";
        string memory expectedSymbol = "brvBVT";

        // We need to call the functions directly since the constructor isn't called
        assertEq(valueTokenFacet.name(), expectedName);
        assertEq(valueTokenFacet.symbol(), expectedSymbol);
    }

    function test_MintValue() public {
        uint256 value = 1000e18;
        uint256 tokenValue = 500e18;
        uint256[MAX_TOKENS] memory limits;

        // First add some value to the closure for alice
        vm.startPrank(alice);
        valueFacet.addValue(
            alice,
            3,
            uint128(value),
            uint128(tokenValue),
            limits
        );
        vm.stopPrank();

        // Now mint value tokens
        vm.startPrank(alice);
        valueTokenFacet.mint(value, tokenValue, 3);
        vm.stopPrank();

        assertEq(valueTokenFacet.balanceOf(alice), value);
    }

    function testExcessValue() public {
        uint256[MAX_TOKENS] memory limits;
        vm.startPrank(alice);
        valueFacet.addValue(alice, 3, 100, 0, limits);
        valueTokenFacet.mint(100, 0, 3);
        vm.expectRevert();
        // Can't add to value when it is already full.
        valueTokenFacet.burn(100, 0, 1);
        vm.stopPrank();
    }

    function test_MintValue_RevertWhenTokenValueExceedsValue() public {
        uint256 value = 1000e18;
        uint256 tokenValue = 1500e18; // Token value exceeds total value

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueTokenFacet.InsufficientValueForBgt.selector,
                value,
                tokenValue
            )
        );
        valueTokenFacet.mint(value, tokenValue, 3);
        vm.stopPrank();
    }

    function test_BurnValue() public {
        uint256 value = 1000e18;
        uint256 tokenValue = 500e18;
        uint256[MAX_TOKENS] memory limits;

        // First add some value to the closure for alice
        vm.startPrank(alice);
        valueFacet.addValue(
            alice,
            3,
            uint128(value),
            uint128(tokenValue),
            limits
        );

        // First mint some tokens
        valueTokenFacet.mint(value, tokenValue, 3);

        vm.expectRevert();
        valueFacet.removeValue(
            alice,
            3,
            uint128(value),
            uint128(tokenValue),
            limits
        );

        valueTokenFacet.burn(value, tokenValue, 3);

        assertEq(valueTokenFacet.balanceOf(alice), 0);

        // Now remove the value and verify we get back similar amounts
        uint256[MAX_TOKENS] memory receivedBalances = valueFacet.removeValue(
            alice,
            3,
            uint128(value),
            uint128(tokenValue),
            limits
        );
        vm.stopPrank();

        // Verify we received balances for the tokens in the closure
        ClosureId cid = ClosureId.wrap(3);
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            if (cid.contains(i)) {
                assertTrue(
                    receivedBalances[i] == (value / 2),
                    "Should receive non-zero balance for token in closure"
                );
            }
        }
    }

    function test_BurnValue_RevertWhenTokenValueExceedsValue() public {
        uint256 value = 1000e18;
        uint256 tokenValue = 1500e18; // Token value exceeds total value
        uint256[MAX_TOKENS] memory limits;

        // First add some value to the closure for alice
        vm.startPrank(alice);
        valueFacet.addValue(alice, 3, uint128(value), uint128(500e18), limits);
        vm.stopPrank();

        // First mint some tokens
        vm.startPrank(alice);
        valueTokenFacet.mint(value, 500e18, 3);
        vm.stopPrank();

        // Try to burn with invalid token value
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueTokenFacet.InsufficientValueForBgt.selector,
                value,
                tokenValue
            )
        );
        valueTokenFacet.burn(value, tokenValue, 3);
        vm.stopPrank();
    }

    function test_BurnValue_RevertWhenInsufficientBalance() public {
        uint256 value = 1000e18;
        uint256 tokenValue = 500e18;

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                0,
                value
            )
        );
        valueTokenFacet.burn(value, tokenValue, 3);
        vm.stopPrank();
    }

    function test_TransferValue() public {
        uint256 value = 1000e18;
        uint256 tokenValue = 500e18;
        uint256[MAX_TOKENS] memory limits;

        // First add some value to the closure for alice
        vm.startPrank(alice);
        valueFacet.addValue(
            alice,
            3,
            uint128(value),
            uint128(tokenValue),
            limits
        );
        vm.stopPrank();

        // Mint tokens to alice
        vm.startPrank(alice);
        valueTokenFacet.mint(value, tokenValue, 3);
        vm.stopPrank();

        // Transfer from alice to bob
        vm.startPrank(alice);
        valueTokenFacet.transfer(bob, value);
        vm.stopPrank();

        assertEq(valueTokenFacet.balanceOf(alice), 0);
        assertEq(valueTokenFacet.balanceOf(bob), value);
    }

    function test_MintTransferBurnFlow() public {
        uint256 value = 1000e18;
        uint256 tokenValue = 500e18;
        uint256[MAX_TOKENS] memory limits;

        // First add some value to the closure for alice
        vm.startPrank(alice);
        valueFacet.addValue(
            alice,
            3,
            uint128(value),
            uint128(tokenValue),
            limits
        );
        vm.stopPrank();

        // Mint tokens to alice
        vm.startPrank(alice);
        valueTokenFacet.mint(value, tokenValue, 3);
        vm.stopPrank();

        // Verify alice has the tokens
        assertEq(valueTokenFacet.balanceOf(alice), value);
        assertEq(valueTokenFacet.balanceOf(bob), 0);

        // Transfer from alice to bob
        vm.startPrank(alice);
        valueTokenFacet.transfer(bob, value);
        vm.stopPrank();

        // Verify transfer was successful
        assertEq(valueTokenFacet.balanceOf(alice), 0);
        assertEq(valueTokenFacet.balanceOf(bob), value);

        // Now bob burns the tokens
        vm.startPrank(bob);
        valueTokenFacet.burn(value, tokenValue, 3);
        vm.stopPrank();

        // Verify final balances
        assertEq(valueTokenFacet.balanceOf(alice), 0);
        assertEq(valueTokenFacet.balanceOf(bob), 0);
    }

    function test_unstakeFromLock() public {
        uint256[MAX_TOKENS] memory limits;
        vm.prank(alice);
        valueFacet.addValue(alice, 3, 100e18, 0, limits);
        vm.prank(owner);
        lockFacet.lock(tokens[1]);
        vm.startPrank(alice);
        vm.expectRevert();
        valueTokenFacet.mint(100e18, 0, 3);
        vm.stopPrank();
    }
}
