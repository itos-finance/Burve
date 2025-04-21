// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {IDiamondCut} from "Commons/Diamond/interfaces/IDiamondCut.sol";
import {ValueFacet} from "../src/multi/facets/ValueFacet.sol";

contract ValueFacetCut is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address diamond = address(0xcd4d38D6E6B218BaBF95d8657C00186cbBE6Fc24);

        // Get the new value facet address from the environment
        address newValueFacet = address(new ValueFacet());

        // Get the function selectors for the value facet
        bytes4[] memory valueSelectors = new bytes4[](8);
        valueSelectors[0] = ValueFacet.addValue.selector;
        valueSelectors[1] = ValueFacet.addValueSingle.selector;
        valueSelectors[2] = ValueFacet.addSingleForValue.selector;
        valueSelectors[3] = ValueFacet.removeValue.selector;
        valueSelectors[4] = ValueFacet.removeValueSingle.selector;
        valueSelectors[5] = ValueFacet.removeSingleForValue.selector;
        valueSelectors[6] = ValueFacet.queryValue.selector;
        valueSelectors[7] = ValueFacet.collectEarnings.selector;

        // Create the facet cut
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: newValueFacet,
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: valueSelectors
        });

        // Perform the diamond cut
        IDiamondCut(diamond).diamondCut(cuts, address(0), "");

        vm.stopBroadcast();
    }
}
