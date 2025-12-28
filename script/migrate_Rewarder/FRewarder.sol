// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {IDiamondCut} from "Commons/Diamond/interfaces/IDiamondCut.sol";

import {BurveForkableTest} from "../../test/integrations/Fork.u.sol";
import {Rewarder} from "../../src/integrations/Rewarder.sol";
import {IBurveMultiValue} from "../../src/multi/interfaces/IBurveMultiValue.sol";
import {ValueFacet, ValueSingleFacet} from "../../src/multi/facets/ValueFacet.sol";

contract FRewarder is BurveForkableTest {
    address constant MULTISIG = 0x9293f9FFC43F6fce06290285919541E963D87F51;
    address constant OMNIPOOL = 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;
    address constant WBERA = 0x6969696969696969696969696969696969696969;
    address constant USER = 0xbe7dC5cC7977ac378ead410869D6c96f1E6C773e;

    function forkSetup() internal override {
        super.forkSetup();

        address facet = address(new ValueFacet());
        bytes4[] memory valueSelectors = new bytes4[](3);
        valueSelectors[0] = IBurveMultiValue.addValue.selector;
        valueSelectors[1] = IBurveMultiValue.removeValue.selector;
        valueSelectors[2] = IBurveMultiValue.collectEarnings.selector;

        vm.startPrank(MULTISIG);
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: facet,
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: valueSelectors
        });
        IDiamondCut(OMNIPOOL).diamondCut(cuts, address(0), "");
        vm.stopPrank();
    }

    function testFRewarder() public {
        Rewarder rewarder = new Rewarder(OMNIPOOL);
        deal(WBERA, address(this), type(uint256).max);
        IERC20(WBERA).approve(address(rewarder), type(uint256).max);
        address[] memory tokens = simplexFacet.getTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            rewarder.fund(tokens[i], WBERA, 1 << 96, 100e18);
        }
        uint16 closureId = 63;
        int256[] memory bonuses = rewarder.viewRewards(USER, closureId);
        vm.startPrank(USER);
        uint256 balanceBefore = IERC20(WBERA).balanceOf(USER);
        IBurveMultiValue(OMNIPOOL).collectEarnings(
            address(rewarder),
            closureId
        );
        uint256 balanceAfter = IERC20(WBERA).balanceOf(USER);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }
}
