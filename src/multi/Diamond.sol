// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {LibDiamond} from "Commons/Diamond/libraries/LibDiamond.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";

import {DiamondCutFacet} from "Commons/Diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "Commons/Diamond/facets/DiamondLoupeFacet.sol";

import {IDiamondCut} from "Commons/Diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "Commons/Diamond/interfaces/IDiamondLoupe.sol";
import {DiamondLoupeFacet} from "Commons/Diamond/facets/DiamondLoupeFacet.sol";
import {IERC173} from "Commons/ERC/interfaces/IERC173.sol";
import {IERC165} from "Commons/ERC/interfaces/IERC165.sol";

import {SwapFacet} from "./facets/SwapFacet.sol";
import {LiqFacet} from "./facets/LiqFacet.sol";
import {SimplexFacet} from "./facets/SimplexFacet.sol";
import {EdgeFacet} from "./facets/EdgeFacet.sol";

error FunctionNotFound(bytes4 _functionSelector);

contract SimplexDiamond is IDiamond {
    constructor(address swapFacet, address liqFacet, address simplexFacet) {
        AdminLib.initOwner(msg.sender);

        FacetCut[] memory cuts = new FacetCut[](7);

        {
            bytes4[] memory cutFunctionSelectors = new bytes4[](1);
            cutFunctionSelectors[0] = DiamondCutFacet.diamondCut.selector;

            cuts[0] = FacetCut({
                facetAddress: address(new DiamondCutFacet()),
                action: FacetCutAction.Add,
                functionSelectors: cutFunctionSelectors
            });
        }

        {
            bytes4[] memory loupeFacetSelectors = new bytes4[](5);
            loupeFacetSelectors[0] = DiamondLoupeFacet.facets.selector;
            loupeFacetSelectors[1] = DiamondLoupeFacet
                .facetFunctionSelectors
                .selector;
            loupeFacetSelectors[2] = DiamondLoupeFacet.facetAddresses.selector;
            loupeFacetSelectors[3] = DiamondLoupeFacet.facetAddress.selector;
            loupeFacetSelectors[4] = DiamondLoupeFacet
                .supportsInterface
                .selector;
            cuts[1] = FacetCut({
                facetAddress: address(new DiamondLoupeFacet()),
                action: FacetCutAction.Add,
                functionSelectors: loupeFacetSelectors
            });
        }

        {
            bytes4[] memory adminSelectors = new bytes4[](3);
            adminSelectors[0] = BaseAdminFacet.transferOwnership.selector;
            adminSelectors[1] = BaseAdminFacet.owner.selector;
            adminSelectors[2] = BaseAdminFacet.adminRights.selector;
            cuts[2] = FacetCut({
                facetAddress: address(new BaseAdminFacet()),
                action: FacetCutAction.Add,
                functionSelectors: adminSelectors
            });
        }

        {
            bytes4[] memory liqSelectors = new bytes4[](2);
            liqSelectors[0] = LiqFacet.addLiq.selector;
            liqSelectors[1] = LiqFacet.removeLiq.selector;
            cuts[3] = FacetCut({
                facetAddress: liqFacet,
                action: FacetCutAction.Add,
                functionSelectors: liqSelectors
            });
        }

        {
            bytes4[] memory swapSelectors = new bytes4[](1);
            swapSelectors[0] = SwapFacet.swap.selector;
            cuts[4] = FacetCut({
                facetAddress: swapFacet,
                action: FacetCutAction.Add,
                functionSelectors: swapSelectors
            });
        }

        {
            bytes4[] memory simplexSelectors = new bytes4[](6);
            simplexSelectors[0] = SimplexFacet.getVertexId.selector;
            simplexSelectors[1] = SimplexFacet.addVertex.selector;
            simplexSelectors[2] = SimplexFacet.withdrawFees.selector;
            simplexSelectors[3] = SimplexFacet.setDefaultEdge.selector;
            simplexSelectors[4] = SimplexFacet.setName.selector;
            simplexSelectors[5] = SimplexFacet.getName.selector;
            cuts[5] = FacetCut({
                facetAddress: simplexFacet,
                action: FacetCutAction.Add,
                functionSelectors: simplexSelectors
            });
        }

        {
            // Edge facet is so small we just deploy it ourselves.
            bytes4[] memory edgeSelectors = new bytes4[](2);
            edgeSelectors[0] = EdgeFacet.setEdge.selector;
            edgeSelectors[1] = EdgeFacet.setEdgeFee.selector;
            cuts[6] = FacetCut({
                facetAddress: address(new EdgeFacet()),
                action: FacetCutAction.Add,
                functionSelectors: edgeSelectors
            });
        }

        // Finally, install all the cuts and don't use an initialization contract.
        LibDiamond.diamondCut(cuts, address(0), "");

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;
    }

    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        // get diamond storage
        assembly {
            ds.slot := position
        }
        // get facet from function selector
        address facet = ds
            .facetAddressAndSelectorPosition[msg.sig]
            .facetAddress;
        if (facet == address(0)) {
            revert FunctionNotFound(msg.sig);
        }
        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}
}
