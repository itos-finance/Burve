// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MultiSetupTest} from "../../facets/MultiSetup.u.sol";
import {Compounder, SingleDeposit} from "../../../src/integrations/compounder/Compounder.sol";
import {IBurveMultiValue} from "../../../src/multi/interfaces/IBurveMultiValue.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract CompounderTest is MultiSetupTest {
    Compounder public compounder;
    uint16 constant CID = 0x3; // closure with tokens 0 and 1

    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(2);
        _fundAccount(alice);
        _fundAccount(owner);
        vm.startPrank(owner);

        // Set fees: 1 basis point edge fee, no protocol take
        uint256 oneX128 = 1 << 128;
        simplexFacet.setSimplexFees(uint128(oneX128 / 10000), 0);

        _initializeClosure(CID, 100e18);
        vm.stopPrank();

        compounder = new Compounder(diamond);

        // Fund compounder so it can deposit
        vm.startPrank(owner);
        MockERC20(tokens[0]).mint(address(compounder), 1e24);
        MockERC20(tokens[1]).mint(address(compounder), 1e24);
        vm.stopPrank();

        // Compounder adds value (it becomes the position owner via RFTPayer callback)
        // The compounder is an RFTPayer, so diamond will call tokenRequestCB
        vm.prank(address(compounder));
        uint256[MAX_TOKENS] memory limits;
        IBurveMultiValue(diamond).addValue(address(compounder), CID, 10e18, 0, limits);
    }

    function testCompound() public {
        // Generate fees via swaps
        vm.startPrank(alice);
        MockERC20(tokens[0]).approve(diamond, type(uint256).max);
        MockERC20(tokens[1]).approve(diamond, type(uint256).max);

        // Do several swaps to accumulate fees
        swapFacet.swap(alice, tokens[0], tokens[1], 1e18, 0, CID);
        swapFacet.swap(alice, tokens[1], tokens[0], 1e18, 0, CID);
        swapFacet.swap(alice, tokens[0], tokens[1], 1e18, 0, CID);
        vm.stopPrank();

        // Check that earnings exist
        (, , uint256[MAX_TOKENS] memory earnings, ) = valueFacet.queryValue(
            address(compounder),
            CID
        );
        bool hasEarnings = false;
        for (uint256 i = 0; i < 2; i++) {
            if (earnings[i] > 0) hasEarnings = true;
        }
        assertTrue(hasEarnings, "should have earnings after swaps");

        // Build single deposits from the earned amounts
        // We skip addValue (set to 0) and just do single deposits for simplicity
        uint256[MAX_TOKENS] memory addValueLimits;
        SingleDeposit[] memory singles = new SingleDeposit[](2);
        for (uint256 i = 0; i < 2; i++) {
            if (earnings[i] > 0) {
                singles[i] = SingleDeposit({
                    token: tokens[i],
                    amount: uint128(earnings[i]),
                    minValue: 0
                });
            }
        }

        // Compound — anyone can call it, position belongs to compounder
        // addValue recipient = msg.sender = alice here, but we use singles which go to alice too
        // Actually the compound function uses msg.sender as recipient for addValue/addSingleForValue
        // So alice gets the new value. Let's call from a neutral address.
        vm.prank(alice);
        compounder.compound(CID, 0, addValueLimits, singles);

        // Verify: alice should have received value from the compounded earnings
        (uint256 aliceValue, , , ) = valueFacet.queryValue(alice, CID);
        assertGt(aliceValue, 0, "alice should have value from compounded earnings");

        // Verify: no tokens stuck in compounder
        for (uint256 i = 0; i < 2; i++) {
            uint256 bal = IERC20(tokens[i]).balanceOf(address(compounder));
            assertEq(bal, 0, "no tokens should be stuck in compounder");
        }

        // Verify: compounder's earnings should be negligible after compound
        // (small dust may accrue from the addSingleForValue deposits themselves)
        (, , uint256[MAX_TOKENS] memory earningsAfter, ) = valueFacet.queryValue(
            address(compounder),
            CID
        );
        for (uint256 i = 0; i < 2; i++) {
            assertLt(earningsAfter[i], earnings[i] / 100, "earnings should be negligible after compound");
        }
    }
}
