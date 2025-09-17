// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {IDiamondCut} from "Commons/Diamond/interfaces/IDiamondCut.sol";
import {BaseScript} from "../utils/BaseScript.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {SimplexSetFacet} from "../../src/multi/facets/SimplexFacet.sol";

contract FacetCut {
    address constant DIAMOND =
        address(0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089);
    address constant UPDATER =
        address(0xEAD30c685F6B4817722018E3205c5f2edD5403DB);
    address constant SIMPLEX_SET_FACET =
        address(0x6c93fc895c90C9c7A6897858A340f6e36dF0022B);

    BaseAdminFacet adminFacet;

    constructor() {
        adminFacet = BaseAdminFacet(DIAMOND);
    }

    function acceptOwnership() external {
        adminFacet.acceptOwnership();
    }

    function performFacetCut() external {
        // Get all function selectors for SimplexSetFacet
        bytes4[] memory simplexSetSelectors = new bytes4[](8);
        simplexSetSelectors[0] = SimplexSetFacet.setEX128.selector;
        simplexSetSelectors[1] = SimplexSetFacet.setAdjustor.selector;
        simplexSetSelectors[2] = SimplexSetFacet.setBGTExchanger.selector;
        simplexSetSelectors[3] = SimplexSetFacet.setInitTarget.selector;
        simplexSetSelectors[4] = SimplexSetFacet.setSearchParams.selector;
        simplexSetSelectors[5] = SimplexSetFacet.setName.selector;
        simplexSetSelectors[6] = SimplexSetFacet.setSimplexFees.selector;
        simplexSetSelectors[7] = SimplexSetFacet.setEdgeFee.selector;

        // Create facet cut
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: SIMPLEX_SET_FACET,
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: simplexSetSelectors
        });

        // Execute the diamond cut
        IDiamondCut(DIAMOND).diamondCut(cuts, address(0), "");
    }

    function transferOwnership() external {
        // note: we transfer ownership to the UPDATER contract to complete the update for now
        adminFacet.transferOwnership(UPDATER);
    }
}
