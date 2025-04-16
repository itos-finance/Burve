// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "./MultiSetup.u.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {VaultType} from "../../src/multi/vertex/VaultProxy.sol";
import {TransferHelper} from "../../src/TransferHelper.sol";

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

    function testAdds() public {
        // Test that valueFacet.addValueSingle and addSingleForValue using 6 decimals on token 2 is the same value as using 18 on token 0.
        // It'll be roughly the same because the target will change, with each add but they shouldn't be off by 12 decimals of course.
        // Check balances before and after to double check transfer amounts.
    }

    function testSwap() public {
        // Test that swapping 18 decimals of one token gets us 6 decimals of another,
        // but the amount limit happens on nominal values so an 18 decimal limit still works
        // Like this should work even though the actual out amount will be something around 99
        // swapFacet.swap(alice, tokens[0], tokens[2], 1e14, .98e14, 0x7);
        // double check balances before and after for decimal accuracy.
    }
}
