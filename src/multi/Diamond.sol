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

import {Store} from "./Store.sol";
import {BurveFacets} from "../InitLib.sol";
import {SwapFacet} from "./facets/SwapFacet.sol";
import {LiqFacet} from "./facets/LiqFacet.sol";
import {SimplexFacet} from "./facets/SimplexFacet.sol";
import {EdgeFacet} from "./facets/EdgeFacet.sol";
import {ViewFacet} from "./facets/ViewFacet.sol";
import {LockFacet} from "./facets/LockFacet.sol";
import {VaultFacet} from "./facets/VaultFacet.sol";
import {IAdjustor} from "../integrations/adjustor/IAdjustor.sol";

error FunctionNotFound(bytes4 _functionSelector);

contract SimplexDiamond is IDiamond {
    constructor(BurveFacets memory facets) {
        AdminLib.initOwner(msg.sender);
        Store.load().adjustor = IAdjustor(facets.adjustor);

        FacetCut[] memory cuts = new FacetCut[](10);

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
            bytes4[] memory liqSelectors = new bytes4[](3);
            liqSelectors[0] = LiqFacet.addLiq.selector;
            liqSelectors[1] = LiqFacet.removeLiq.selector;
            liqSelectors[2] = LiqFacet.viewRemoveLiq.selector;
            cuts[3] = FacetCut({
                facetAddress: facets.liqFacet,
                action: FacetCutAction.Add,
                functionSelectors: liqSelectors
            });
        }

        {
            bytes4[] memory swapSelectors = new bytes4[](3);
            swapSelectors[0] = SwapFacet.swap.selector;
            swapSelectors[1] = SwapFacet.simSwap.selector;
            swapSelectors[2] = SwapFacet.getSqrtPrice.selector;
            cuts[4] = FacetCut({
                facetAddress: facets.swapFacet,
                action: FacetCutAction.Add,
                functionSelectors: swapSelectors
            });
        }

        {
            bytes4[] memory simplexSelectors = new bytes4[](10);
            simplexSelectors[0] = SimplexFacet.getVertexId.selector;
            simplexSelectors[1] = SimplexFacet.addVertex.selector;
            simplexSelectors[2] = SimplexFacet.getTokens.selector;
            simplexSelectors[3] = SimplexFacet.getIndexes.selector;
            simplexSelectors[4] = SimplexFacet.numVertices.selector;
            simplexSelectors[5] = SimplexFacet.withdrawFees.selector;
            simplexSelectors[6] = SimplexFacet.setDefaultEdge.selector;
            simplexSelectors[7] = SimplexFacet.setName.selector;
            simplexSelectors[8] = SimplexFacet.getName.selector;
            simplexSelectors[9] = SimplexFacet.setAdjustor.selector;
            cuts[5] = FacetCut({
                facetAddress: facets.simplexFacet,
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

        {
            bytes4[] memory selectors = new bytes4[](8);
            selectors[0] = ViewFacet.getEdge.selector;
            selectors[1] = ViewFacet.getVertex.selector;
            selectors[2] = ViewFacet.getAssetShares.selector;
            selectors[3] = ViewFacet.getDefaultEdge.selector;
            selectors[4] = ViewFacet.getClosureId.selector;
            selectors[5] = ViewFacet.getPriceX128.selector;
            selectors[6] = ViewFacet.getTokenIndex.selector;
            selectors[7] = ViewFacet.isTokenInClosure.selector;

            cuts[7] = IDiamond.FacetCut({
                facetAddress: address(new ViewFacet()),
                action: IDiamond.FacetCutAction.Add,
                functionSelectors: selectors
            });
        }

        {
            bytes4[] memory selectors = new bytes4[](7);
            selectors[0] = LockFacet.lock.selector;
            selectors[1] = LockFacet.unlock.selector;
            selectors[2] = LockFacet.isLocked.selector;
            selectors[3] = LockFacet.addLocker.selector;
            selectors[4] = LockFacet.addUnlocker.selector;
            selectors[5] = LockFacet.removeLocker.selector;
            selectors[6] = LockFacet.removeUnlocker.selector;

            cuts[8] = IDiamond.FacetCut({
                facetAddress: address(new LockFacet()),
                action: IDiamond.FacetCutAction.Add,
                functionSelectors: selectors
            });
        }

        {
            bytes4[] memory selectors = new bytes4[](7);
            selectors[0] = VaultFacet.addVault.selector;
            selectors[1] = VaultFacet.acceptVault.selector;
            selectors[2] = VaultFacet.vetoVault.selector;
            selectors[3] = VaultFacet.removeVault.selector;
            selectors[4] = VaultFacet.transferBalance.selector;
            selectors[5] = VaultFacet.hotSwap.selector;
            selectors[6] = VaultFacet.viewVaults.selector;

            cuts[9] = IDiamond.FacetCut({
                facetAddress: facets.vaultFacet,
                action: IDiamond.FacetCutAction.Add,
                functionSelectors: selectors
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
