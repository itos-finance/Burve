// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {BaseScript} from "./BaseScript.sol";
import {ValueFacet} from "../../src/facets/ValueFacet.sol";

contract Adjust is BaseScript {
    function run() external {
        vm.startBroadcast(_getPrivateKey());

        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = StoreManipulatorFacet.setClosureValue.selector;
        selectors[1] = StoreManipulatorFacet.setClosureFees.selector;
        selectors[2] = StoreManipulatorFacet.setProtocolEarnings.selector;
        selectors[3] = StoreManipulatorFacet.getVertex.selector;

        cuts[0] = (
            IDiamond.FacetCut({
                facetAddress: address(new StoreManipulatorFacet()),
                action: IDiamond.FacetCutAction.Add,
                functionSelectors: selectors
            })
        );

        DiamondCutFacet cutFacet = DiamondCutFacet(diamond);
        cutFacet.diamondCut(cuts, address(0), "");

        vm.stopBroadcast();
    }
}
