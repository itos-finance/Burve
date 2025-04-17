// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "./MultiSetup.u.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {VaultType} from "../../src/multi/vertex/VaultProxy.sol";
import {TransferHelper} from "../../src/TransferHelper.sol";
import {TokenRegistry, MAX_TOKENS} from "../../src/multi/Token.sol";

contract AdjustmentTest is MultiSetupTest {
    function setUp() public {
        _newDiamond();
        _newTokens(2);

        // Add a 6 decimal token.
        tokens.push(address(new MockERC20("Test Token 3", "TEST3", 6)));
        vaults.push(
            IERC4626(
                address(new MockERC4626(ERC20(tokens[2]), "vault 3", "V3"))
            )
        );
        simplexFacet.addVertex(tokens[2], address(vaults[2]), VaultType.E4626);
        _fundAccount(address(this));
        _initializeClosure(0x7, 100e24);
    }

    function testInitLiq() public view {
        // Check the initial liquidity minted is in "equal" proportion according to the decimal.
        assertEq(MockERC20(tokens[0]).balanceOf(address(vaults[0])), 100e24);
        assertEq(MockERC20(tokens[1]).balanceOf(address(vaults[1])), 100e24);
        assertEq(MockERC20(tokens[2]).balanceOf(address(vaults[2])), 100e12);
    }

    function testAddValue() public {
        // Get initial balances
        uint256 initialBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 initialBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Add value using both tokens
        uint128 valueToAdd = 1e18;
        uint128 bgtValue = 0;
        valueFacet.addValue(address(this), 0x7, valueToAdd, bgtValue);

        // Check final balances
        uint256 finalBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 finalBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Calculate amounts spent
        uint256 spent0 = initialBalance0 - finalBalance0;
        uint256 spent2 = initialBalance2 - finalBalance2;

        // Verify amounts are roughly equivalent in value
        assertApproxEqRel(spent0, spent2 * 1e12, 0.01e18); // Allow 1% difference due to price impact
    }

    function testAddValueSingle() public {
        // Get initial balances
        uint256 initialBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 initialBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Add value using token0 (18 decimals)
        uint128 valueToAdd = 1e18;
        valueFacet.addValueSingle(
            address(this),
            0x7,
            valueToAdd,
            0,
            tokens[0],
            0
        );

        // Add same value using token2 (6 decimals)
        valueFacet.addValueSingle(
            address(this),
            0x7,
            valueToAdd,
            0,
            tokens[2],
            0
        );

        // Check final balances
        uint256 finalBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 finalBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Calculate amounts spent
        uint256 spent0 = initialBalance0 - finalBalance0;
        uint256 spent2 = initialBalance2 - finalBalance2;

        // Verify amounts are roughly equivalent in value
        assertApproxEqRel(spent0, spent2 * 1e12, 0.01e18); // Allow 1% difference due to price impact
    }

    function testAddSingleForValue() public {
        // Get initial balances
        uint256 initialBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 initialBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Add value using token0 (18 decimals)
        uint128 amountToAdd = 1e18; // 1 token0
        uint128 minValue = 0;
        valueFacet.addSingleForValue(
            address(this),
            0x7,
            tokens[0],
            amountToAdd,
            0,
            minValue
        );

        // Add value using token2 (6 decimals)
        uint128 amountToAdd2 = 1e6; // 1 token2
        valueFacet.addSingleForValue(
            address(this),
            0x7,
            tokens[2],
            amountToAdd2,
            0,
            minValue
        );

        // Check final balances
        uint256 finalBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 finalBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Calculate amounts spent
        uint256 spent0 = initialBalance0 - finalBalance0;
        uint256 spent2 = initialBalance2 - finalBalance2;

        // Verify amounts are roughly equivalent in value
        assertApproxEqRel(spent0, spent2 * 1e12, 0.01e18); // Allow 1% difference due to price impact
    }

    function testRemoveValue() public {
        // First add some value to remove
        uint128 valueToAdd = 1e18;
        valueFacet.addValueSingle(
            address(this),
            0x7,
            valueToAdd,
            0,
            tokens[0],
            0
        );
        valueFacet.addValueSingle(
            address(this),
            0x7,
            valueToAdd,
            0,
            tokens[2],
            0
        );

        // Get initial balances
        uint256 initialBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 initialBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Query the total value
        (
            uint256 totalValue,
            uint256 bgtValue,
            uint256[MAX_TOKENS] memory earnings,
            uint256 bgtEarnings
        ) = valueFacet.queryValue(address(this), 0x7);

        // Remove value using both tokens
        uint128 valueToRemove = uint128(totalValue);
        uint128 bgtValueToRemove = 0;
        valueFacet.removeValue(
            address(this),
            0x7,
            valueToRemove,
            bgtValueToRemove
        );

        // Check final balances
        uint256 finalBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 finalBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Calculate amounts received
        uint256 received0 = finalBalance0 - initialBalance0;
        uint256 received2 = finalBalance2 - initialBalance2;

        // Verify amounts are roughly equivalent in value
        assertApproxEqRel(received0, received2 * 1e12, 0.01e18); // Allow 1% difference due to fees/price impact
    }

    function testRemoveValueSingle() public {
        // First add some value to remove
        uint128 valueToAdd = 1e18;
        valueFacet.addValueSingle(
            address(this),
            0x7,
            valueToAdd,
            0,
            tokens[0],
            0
        );
        valueFacet.addValueSingle(
            address(this),
            0x7,
            valueToAdd,
            0,
            tokens[2],
            0
        );

        // Get initial balances
        uint256 initialBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 initialBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Query the total value
        (
            uint256 totalValue,
            uint256 bgtValue,
            uint256[MAX_TOKENS] memory earnings,
            uint256 bgtEarnings
        ) = valueFacet.queryValue(address(this), 0x7);

        // Remove value using token0 (18 decimals)
        uint128 valueToRemove = uint128(totalValue / 2);
        uint128 minReceive0 = 0;
        valueFacet.removeValueSingle(
            address(this),
            0x7,
            valueToRemove,
            0,
            tokens[0],
            minReceive0
        );

        // Remove value using token2 (6 decimals)
        uint128 minReceive2 = 0;
        valueFacet.removeValueSingle(
            address(this),
            0x7,
            valueToRemove,
            0,
            tokens[2],
            minReceive2
        );

        // Check final balances
        uint256 finalBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 finalBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Calculate amounts received
        uint256 received0 = finalBalance0 - initialBalance0;
        uint256 received2 = finalBalance2 - initialBalance2;

        // Verify amounts are roughly equivalent in value
        assertApproxEqRel(received0, received2 * 1e12, 0.01e18); // Allow 1% difference due to fees/price impact
    }

    function testRemoveSingleForValue() public {
        // First add some value to remove
        uint128 valueToAdd = 1e18;
        uint128 maxRequired = 1e18;
        valueFacet.addValueSingle(
            address(this),
            0x7,
            valueToAdd,
            0,
            tokens[0],
            0
        );
        valueFacet.addValueSingle(
            address(this),
            0x7,
            valueToAdd,
            0,
            tokens[2],
            0
        );

        // Get initial balances
        uint256 initialBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 initialBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Remove value using token0 (18 decimals)
        uint128 amountToRemove = 1e18; // 1 token0
        uint128 maxValue = type(uint128).max;
        valueFacet.removeSingleForValue(
            address(this),
            0x7,
            tokens[0],
            amountToRemove,
            0,
            0
        );

        // Remove value using token2 (6 decimals)
        uint128 amountToRemove2 = 1e6; // 1 token2
        valueFacet.removeSingleForValue(
            address(this),
            0x7,
            tokens[2],
            amountToRemove2,
            0,
            0
        );

        // Check final balances
        uint256 finalBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 finalBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Calculate amounts received
        uint256 received0 = finalBalance0 - initialBalance0;
        uint256 received2 = finalBalance2 - initialBalance2;

        // Verify amounts are roughly equivalent in value
        assertApproxEqRel(received0, received2 * 1e12, 0.01e18); // Allow 1% difference due to fees/price impact
    }

    function testSwapAdjusted() public {
        // Test that swapping 18 decimals of one token gets us 6 decimals of another,
        // but the amount limit happens on nominal values so an 18 decimal limit still works
        // Like this should work even though the actual out amount will be something around 99
        // swapFacet.swap(alice, tokens[0], tokens[2], 1e14, .98e14, 0x7);
        // double check balances before and after for decimal accuracy.

        // Get initial balances
        uint256 initialBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        uint256 initialBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // Approve tokens for swap
        MockERC20(tokens[0]).approve(address(diamond), type(uint256).max);

        // Swap from token0 (18 decimals) to token2 (6 decimals)
        uint256 amountIn = 1e18; // 1 token0
        uint256 amountLimit = 98e16; // 0.98 token2 (in 6 decimals)
        swapFacet.swap(
            address(this),
            tokens[0],
            tokens[2],
            int256(amountIn),
            amountLimit,
            0x7
        );

        // Check final balances
        // uint256 finalBalance0 = MockERC20(tokens[0]).balanceOf(address(this));
        // uint256 finalBalance2 = MockERC20(tokens[2]).balanceOf(address(this));

        // // Verify the swap amounts
        // uint256 spent0 = initialBalance0 - finalBalance0;
        // uint256 received2 = finalBalance2 - initialBalance2;

        // assertEq(spent0, amountIn, "Incorrect amount spent");
        // assertTrue(
        //     received2 >= amountLimit,
        //     "Received less than minimum amount"
        // );

        // // Now swap back from token2 to token0
        // MockERC20(tokens[2]).approve(address(diamond), type(uint256).max);
        // uint256 amountIn2 = 1e6; // 1 token2
        // uint256 amountLimit2 = 98e12; // 0.98 token0 (in 18 decimals)
        // swapFacet.swap(
        //     address(this),
        //     tokens[2],
        //     tokens[0],
        //     int256(amountIn2),
        //     amountLimit2,
        //     0x7
        // );
    }
}
