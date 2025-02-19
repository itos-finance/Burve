// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "./MultiSetup.u.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {VaultType} from "../../src/multi/VaultProxy.sol";
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

        // Fund alice for all 3 tokens.
        _fundAccount(address(this));
    }

    function testInitLiq() public {
        // Mint some liquidity. We should put them in equal proportion according to their decimals.
        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 100e18;
        amounts[1] = 100e18;
        amounts[2] = 100e6;
        liqFacet.addLiq(address(this), 0x7, amounts);

        uint160 sqrtPX96 = swapFacet.getSqrtPrice(tokens[2], tokens[0]);
        assertEq(sqrtPX96, 1 << 96);

        // Had we minted with equal balances, 3 would be cheap.
        amounts[0] = 0;
        amounts[1] = 0;
        amounts[2] = 100e18 - 100e6;
        liqFacet.addLiq(address(this), 0x7, amounts);
        // This will lower the third tokens price.
        sqrtPX96 = swapFacet.getSqrtPrice(tokens[2], tokens[0]);
        assertLt(sqrtPX96, 1 << 96);
    }

    function testSwap() public {
        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 100e18;
        amounts[1] = 100e18;
        amounts[2] = 100e6;
        liqFacet.addLiq(address(this), 0x7, amounts);

        // Our swap should basically be one for one, adjusted.
        (uint256 x, uint256 y, ) = swapFacet.simSwap(
            tokens[0],
            tokens[1],
            100,
            1 << 95
        );
        assertEq(x, y);

        uint160 limit = tokens[2] < tokens[0] ? 1 << 95 : 1 << 97;
        (, y) = swapFacet.swap(address(this), tokens[2], tokens[0], 10, limit);
        assertEq(y, 1e13);
    }

    function testVault() public {
        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 100e18;
        amounts[1] = 100e18;
        amounts[2] = 100e5;
        liqFacet.addLiq(address(this), 0x7, amounts);

        // Price is currently insufficient.
        uint160 sqrtPX96 = swapFacet.getSqrtPrice(tokens[2], tokens[0]);
        assertLt(sqrtPX96, 1 << 96);

        // Adding some tokens to the vault will skew prices because of the adjustment.
        TransferHelper.safeTransfer(
            tokens[2],
            address(vaults[2]),
            100e6 - 100e5
        );
        sqrtPX96 = swapFacet.getSqrtPrice(tokens[2], tokens[0]);
        assertEq(sqrtPX96, 1 << 96);
    }
}
