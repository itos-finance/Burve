// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {BaseScript} from "./BaseScript.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {IBurveMultiValue} from "../../src/multi/interfaces/IBurveMultiValue.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {DiamondCutFacet} from "Commons/Diamond/facets/DiamondCutFacet.sol";

contract FacetCut is BaseScript {
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = IBurveMultiValue.addValue.selector;
        selectors[1] = IBurveMultiValue.removeValue.selector;
        selectors[2] = IBurveMultiValue.collectEarnings.selector;

        cuts[0] = (
            IDiamond.FacetCut({
                facetAddress: address(new ValueFacet()),
                action: IDiamond.FacetCutAction.Replace,
                functionSelectors: selectors
            })
        );

        DiamondCutFacet cutFacet = DiamondCutFacet(
            address(0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089)
        );
        cutFacet.diamondCut(cuts, address(0), "");

        vm.stopBroadcast();
    }
}
