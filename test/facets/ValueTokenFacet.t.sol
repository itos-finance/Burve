// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MultiSetupTest} from "./MultiSetup.u.sol";
import {ValueTokenFacet} from "../../src/multi/facets/ValueTokenFacet.sol";
import {AssetBookImpl} from "../../src/multi/Asset.sol";
import {Store} from "../../src/multi/Store.sol";
import {SimplexLib} from "../../src/multi/Simplex.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {ClosureId} from "../../src/multi/closure/Id.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract ValueTokenTransferTest is MultiSetupTest {
    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(2);
        _initializeClosure(3, 1e18); // Initialize closure with both tokens
        _initializeClosure(1, 1e18);
        vm.stopPrank();

        _fundAccount(alice);
        _fundAccount(bob);
        _fundAccount(address(this));
    }

    function test_TransferValue() public {
        uint256 value = 1000e18;
        uint256 bgtValue = 500e18;
        uint256[MAX_TOKENS] memory limits;

        // First add some value to the closure for alice
        vm.prank(alice);
        valueFacet.addValue(
            alice,
            3,
            uint128(value),
            uint128(bgtValue),
            limits
        );

        (
            uint256 aValue,
            uint256 aBgtValue,
            uint256[MAX_TOKENS] memory aEarnings,
            uint256 aBgtEarnings
        ) = valueFacet.queryValue(alice, 3);

        assertEq(aValue, value);
        assertEq(aBgtValue, bgtValue);
        assertEq(aEarnings[0], 0);
        assertEq(aEarnings[1], 0);
        assertEq(aBgtEarnings, 0);

        // We'll give some earnings to alice
        MockERC20(tokens[0]).mint(address(vaults[0]), 1000e18); // Mint some tokens to the vault

        (aValue, aBgtValue, aEarnings, ) = valueFacet.queryValue(alice, 3);
        assertEq(aValue, value);
        assertEq(aBgtValue, bgtValue);
        assertGt(aEarnings[0], 900e18);
        assertEq(aEarnings[1], 0);

        // Transfer the whole position to bob now
        // Bob can't do it himself.
        vm.expectRevert(
            abi.encodeWithSelector(
                AssetBookImpl.InsufficientValue.selector,
                0,
                1000e18
            )
        );
        vm.prank(bob);
        valueTokenFacet.transfer(bob, 3, value, bgtValue);

        // Succeeds
        vm.prank(alice);
        valueTokenFacet.transfer(bob, 3, value, bgtValue);

        (
            uint256 bValue,
            uint256 bBgtValue,
            uint256[MAX_TOKENS] memory bEarnings,

        ) = valueFacet.queryValue(bob, 3);
        // Bob gets the value but no earnings.
        assertEq(bValue, value);
        assertEq(bBgtValue, bgtValue);
        assertApproxEqAbs(bEarnings[0], 0, 2); // Rounding in trim.
        assertEq(bEarnings[1], 0);

        // With more earnings, alice's earnings stay the same, while bob's goes up.
        vm.prank(owner);
        simplexFacet.setSimplexFees(uint128((uint256(1) << 128) / 10000), 0);
        swapFacet.swap(address(this), tokens[0], tokens[1], 100e18, 0, 3);
        {
            (
                uint256 newAValue,
                uint256 newABgtValue,
                uint256[MAX_TOKENS] memory newAEarnings,

            ) = valueFacet.queryValue(alice, 3);
            assertEq(newAValue, 0);
            assertEq(newABgtValue, 0);
            assertApproxEqAbs(newAEarnings[0], aEarnings[0], 1);
            assertEq(newAEarnings[1], aEarnings[1]);
        }

        (, , bEarnings, ) = valueFacet.queryValue(bob, 3);
        assertGt(bEarnings[0], 0.99e16);

        // Unless its a growth from reserve appreciation.
        {
            uint256 vaultBalance = MockERC20(tokens[0]).balanceOf(
                address(vaults[0])
            );
            // We'll double the vault balance which should double the earnings sitting in there.
            MockERC20(tokens[0]).mint(address(vaults[0]), vaultBalance);
            // Bob's earnings will double, but ALSO earn from the trim.
        }
        {
            (, , uint256[MAX_TOKENS] memory newAEarnings, ) = valueFacet
                .queryValue(alice, 3);
            assertApproxEqAbs(newAEarnings[0], 2 * aEarnings[0], 3);
            aEarnings[0] = newAEarnings[0];
        }
        {
            (, , uint256[MAX_TOKENS] memory newBEarnings, ) = valueFacet
                .queryValue(bob, 3);
            // 500e18 mint from the balance amount will be trimmed.
            assertGt(newBEarnings[0], 2 * bEarnings[0] + 590e18);
            bEarnings[0] = newBEarnings[0];
        }

        // Alice can't transfer back now that it's bob's.
        vm.expectRevert(
            abi.encodeWithSelector(
                AssetBookImpl.InsufficientValue.selector,
                0,
                400e18
            )
        );
        vm.prank(alice);
        valueTokenFacet.transfer(alice, 3, 400e18, 200e18);
        // But bob can.
        vm.prank(bob);
        valueTokenFacet.transfer(alice, 3, 400e18, 200e18);

        // And now both earn
        {
            uint256 vaultBalance = MockERC20(tokens[0]).balanceOf(
                address(vaults[0])
            );
            // We'll double the vault balance again.
            MockERC20(tokens[0]).mint(address(vaults[0]), vaultBalance);
            // But because both have positions now, they both earn more than the just doubling.
        }
        {
            (, , uint256[MAX_TOKENS] memory newAEarnings, ) = valueFacet
                .queryValue(alice, 3);
            assertGt(newAEarnings[0], 2 * aEarnings[0] + 236e18);
        }
        {
            (, , uint256[MAX_TOKENS] memory newBEarnings, ) = valueFacet
                .queryValue(bob, 3);
            assertGt(newBEarnings[0], 2 * bEarnings[0] + 354e18);
        }
    }

    function test_balanceOf() public {
        uint256 value = 1000e18;
        uint256 bgtValue = 500e18;
        uint256[MAX_TOKENS] memory limits;

        // First add some value to the closure for alice
        vm.prank(alice);
        valueFacet.addValue(
            alice,
            3,
            uint128(value),
            uint128(bgtValue),
            limits
        );

        // Check balanceOf
        (uint256 aValue, uint256 aBgtValue) = valueTokenFacet.balanceOf(
            alice,
            3
        );
        assertEq(aValue, value);
        assertEq(aBgtValue, bgtValue);

        // Check balanceOf for bob (should be zero)
        (uint256 bValue, uint256 bBgtValue) = valueTokenFacet.balanceOf(bob, 3);
        assertEq(bValue, 0);
        assertEq(bBgtValue, 0);

        vm.prank(alice);
        uint256 bobValue = 345e18;
        uint256 bobBgtValue = 123e18;
        valueTokenFacet.transfer(bob, 3, bobValue, bobBgtValue);

        (aValue, aBgtValue) = valueTokenFacet.balanceOf(alice, 3);
        assertEq(aValue, value - bobValue);
        assertEq(aBgtValue, bgtValue - bobBgtValue);

        (bValue, bBgtValue) = valueTokenFacet.balanceOf(bob, 3);
        assertEq(bValue, bobValue);
        assertEq(bBgtValue, bobBgtValue);
    }

    function test_allowance() public {
        uint256 value = 1000e18;
        uint256 bgtValue = 500e18;
        uint256[MAX_TOKENS] memory limits;
        uint256 excess = 1234e15;

        // First add some value to the closure for alice
        vm.prank(alice);
        valueFacet.addValue(
            alice,
            3,
            uint128(value),
            uint128(bgtValue),
            limits
        );

        vm.prank(alice);
        valueFacet.addValue(bob, 3, uint128(value), uint128(bgtValue), limits);

        // Set allowance from alice to bob
        vm.prank(alice);
        valueTokenFacet.approve(bob, 3, value + excess, bgtValue / 2);

        // Check allowance
        (uint256 aValueAllowance, uint256 aBgtAllowance) = valueTokenFacet
            .allowance(alice, bob, 3);
        assertEq(aValueAllowance, value + excess);
        assertEq(aBgtAllowance, bgtValue / 2);

        // Check allowance for bob to alice (should be zero)
        (uint256 bValueAllowance, uint256 bBgtAllowance) = valueTokenFacet
            .allowance(bob, alice, 3);
        assertEq(bValueAllowance, 0);
        assertEq(bBgtAllowance, 0);

        // Alice can't transfer from bob
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueTokenFacet.InsufficientValueAllowance.selector,
                bob,
                alice,
                3,
                0,
                value
            )
        );
        vm.prank(alice);
        valueTokenFacet.transferFrom(bob, alice, 3, value, bgtValue);

        // Bob can't transfer from alice without sufficient bgtValue allowance
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueTokenFacet.InsufficientBgtValueAllowance.selector,
                alice,
                bob,
                3,
                bgtValue / 2,
                bgtValue
            )
        );
        vm.prank(bob);
        valueTokenFacet.transferFrom(alice, bob, 3, value, bgtValue);
        // Give bob sufficient approval.
        vm.prank(alice);
        valueTokenFacet.approve(bob, 3, value + excess, bgtValue + excess);

        // We can't transfer from alice to bob because we're not an approved spender although the recipient is.
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueTokenFacet.InsufficientValueAllowance.selector,
                alice,
                address(this),
                3,
                0,
                value
            )
        );
        valueTokenFacet.transferFrom(alice, bob, 3, value, bgtValue);

        // Finally bob can do the transfer.
        vm.prank(bob);
        valueTokenFacet.transferFrom(alice, bob, 3, value, bgtValue);

        // Check balances after transfer
        (uint256 aValue, uint256 aBgtValue) = valueTokenFacet.balanceOf(
            alice,
            3
        );
        (uint256 bValue, uint256 bBgtValue) = valueTokenFacet.balanceOf(bob, 3);
        assertEq(aValue, 0);
        assertEq(aBgtValue, 0);
        assertEq(bValue, 2 * value);
        assertEq(bBgtValue, 2 * bgtValue);

        // Check allowances after transfer
        (aValueAllowance, aBgtAllowance) = valueTokenFacet.allowance(
            alice,
            bob,
            3
        );
        assertEq(aValueAllowance, excess);
        assertEq(aBgtAllowance, excess);

        // Bob gives alice infinite allowance.
        vm.prank(bob);
        valueTokenFacet.approve(alice, 3, type(uint256).max, type(uint256).max);
        // Check allowance after infinite approval
        (bValueAllowance, bBgtAllowance) = valueTokenFacet.allowance(
            bob,
            alice,
            3
        );
        assertEq(bValueAllowance, type(uint256).max);
        assertEq(bBgtAllowance, type(uint256).max);

        // Alice can now transfer from bob to herself
        vm.prank(alice);
        valueTokenFacet.transferFrom(bob, alice, 3, value, bgtValue);
        // Check balances after transfer
        (aValue, aBgtValue) = valueTokenFacet.balanceOf(alice, 3);
        (bValue, bBgtValue) = valueTokenFacet.balanceOf(bob, 3);
        assertEq(aValue, value);
        assertEq(aBgtValue, bgtValue);
        assertEq(bValue, value);
        assertEq(bBgtValue, bgtValue);
        // Check allowances after transfer
        // Unchanged
        (aValueAllowance, aBgtAllowance) = valueTokenFacet.allowance(
            alice,
            bob,
            3
        );
        assertEq(aValueAllowance, excess);
        assertEq(aBgtAllowance, excess);
        // Infinite so unchanged.
        (bValueAllowance, bBgtAllowance) = valueTokenFacet.allowance(
            bob,
            alice,
            3
        );
        assertEq(bValueAllowance, type(uint256).max, "bValueMax");
        assertEq(bBgtAllowance, type(uint256).max, "bgtMax");

        // Test bob uses allowance even when he transfers to someone else.
        vm.prank(bob);
        valueTokenFacet.approve(alice, 3, value / 2, bgtValue / 2); // Get rid of infinite allowance.
        // Check alice's allowance
        (bValueAllowance, bBgtAllowance) = valueTokenFacet.allowance(
            bob,
            alice,
            3
        );
        assertEq(bValueAllowance, value / 2);
        assertEq(bBgtAllowance, bgtValue / 2);
        // Bob can't transfer more than his allowance now.
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueTokenFacet.InsufficientValueAllowance.selector,
                bob,
                alice,
                3,
                value / 2,
                value
            )
        );
        vm.prank(alice);
        valueTokenFacet.transferFrom(bob, address(this), 3, value, bgtValue);
        // And if he does a successful transfer it still decrements his allowance.
        vm.prank(alice);
        valueTokenFacet.transferFrom(
            bob,
            address(this),
            3,
            value / 2,
            bgtValue / 2
        );
        // Check balances after transfer
        (bValueAllowance, bBgtAllowance) = valueTokenFacet.allowance(
            bob,
            alice,
            3
        );
        assertEq(bValueAllowance, 0);
        assertEq(bBgtAllowance, 0);
    }

    // Same as test_TransferValue but using transferFrom.
    function test_TransferFrom() public {
        uint256 value = 1000e18;
        uint256 bgtValue = 500e18;
        uint256[MAX_TOKENS] memory limits;

        // Give infinite allowances
        vm.prank(alice);
        valueTokenFacet.approve(
            address(this),
            3,
            type(uint256).max,
            type(uint256).max
        );
        vm.prank(bob);
        valueTokenFacet.approve(
            address(this),
            3,
            type(uint256).max,
            type(uint256).max
        );

        // First add some value to the closure for alice
        vm.prank(alice);
        valueFacet.addValue(
            alice,
            3,
            uint128(value),
            uint128(bgtValue),
            limits
        );

        (
            uint256 aValue,
            uint256 aBgtValue,
            uint256[MAX_TOKENS] memory aEarnings,
            uint256 aBgtEarnings
        ) = valueFacet.queryValue(alice, 3);

        assertEq(aValue, value);
        assertEq(aBgtValue, bgtValue);
        assertEq(aEarnings[0], 0);
        assertEq(aEarnings[1], 0);
        assertEq(aBgtEarnings, 0);

        // We'll give some earnings to alice
        MockERC20(tokens[0]).mint(address(vaults[0]), 1000e18); // Mint some tokens to the vault

        (aValue, aBgtValue, aEarnings, ) = valueFacet.queryValue(alice, 3);
        assertEq(aValue, value);
        assertEq(aBgtValue, bgtValue);
        assertGt(aEarnings[0], 900e18);
        assertEq(aEarnings[1], 0);

        // Transfer the whole position to bob now
        // Bob can't do it himself.
        vm.expectRevert(
            abi.encodeWithSelector(
                AssetBookImpl.InsufficientValue.selector,
                0,
                1000e18
            )
        );
        valueTokenFacet.transferFrom(bob, alice, 3, value, bgtValue);

        // Succeeds
        valueTokenFacet.transferFrom(alice, bob, 3, value, bgtValue);

        (
            uint256 bValue,
            uint256 bBgtValue,
            uint256[MAX_TOKENS] memory bEarnings,

        ) = valueFacet.queryValue(bob, 3);
        // Bob gets the value but no earnings.
        assertEq(bValue, value);
        assertEq(bBgtValue, bgtValue);
        assertApproxEqAbs(bEarnings[0], 0, 2); // Rounding in trim.
        assertEq(bEarnings[1], 0);

        // With more earnings, alice's earnings stay the same, while bob's goes up.
        vm.prank(owner);
        simplexFacet.setSimplexFees(uint128((uint256(1) << 128) / 10000), 0);
        swapFacet.swap(address(this), tokens[0], tokens[1], 100e18, 0, 3);
        {
            (
                uint256 newAValue,
                uint256 newABgtValue,
                uint256[MAX_TOKENS] memory newAEarnings,

            ) = valueFacet.queryValue(alice, 3);
            assertEq(newAValue, 0);
            assertEq(newABgtValue, 0);
            assertApproxEqAbs(newAEarnings[0], aEarnings[0], 1);
            assertEq(newAEarnings[1], aEarnings[1]);
        }

        (, , bEarnings, ) = valueFacet.queryValue(bob, 3);
        assertGt(bEarnings[0], 0.99e16);

        // Unless its a growth from reserve appreciation.
        {
            uint256 vaultBalance = MockERC20(tokens[0]).balanceOf(
                address(vaults[0])
            );
            // We'll double the vault balance which should double the earnings sitting in there.
            MockERC20(tokens[0]).mint(address(vaults[0]), vaultBalance);
            // Bob's earnings will double, but ALSO earn from the trim.
        }
        {
            (, , uint256[MAX_TOKENS] memory newAEarnings, ) = valueFacet
                .queryValue(alice, 3);
            assertApproxEqAbs(newAEarnings[0], 2 * aEarnings[0], 3);
            aEarnings[0] = newAEarnings[0];
        }
        {
            (, , uint256[MAX_TOKENS] memory newBEarnings, ) = valueFacet
                .queryValue(bob, 3);
            // 500e18 mint from the balance amount will be trimmed.
            assertGt(newBEarnings[0], 2 * bEarnings[0] + 590e18);
            bEarnings[0] = newBEarnings[0];
        }

        // Alice can't transfer back now that it's bob's.
        vm.expectRevert(
            abi.encodeWithSelector(
                AssetBookImpl.InsufficientValue.selector,
                0,
                400e18
            )
        );
        valueTokenFacet.transferFrom(alice, alice, 3, 400e18, 200e18);
        // But bob can.
        valueTokenFacet.transferFrom(bob, alice, 3, 400e18, 200e18);

        // And now both earn
        {
            uint256 vaultBalance = MockERC20(tokens[0]).balanceOf(
                address(vaults[0])
            );
            // We'll double the vault balance again.
            MockERC20(tokens[0]).mint(address(vaults[0]), vaultBalance);
            // But because both have positions now, they both earn more than the just doubling.
        }
        {
            (, , uint256[MAX_TOKENS] memory newAEarnings, ) = valueFacet
                .queryValue(alice, 3);
            assertGt(newAEarnings[0], 2 * aEarnings[0] + 236e18);
        }
        {
            (, , uint256[MAX_TOKENS] memory newBEarnings, ) = valueFacet
                .queryValue(bob, 3);
            assertGt(newBEarnings[0], 2 * bEarnings[0] + 354e18);
        }
    }
}

/// The value token tests for staking and unstaking value.
/* contract ValueTokenFacetTest is MultiSetupTest {
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
 */
