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
import {BurveFacets} from "./InitLib.sol";
import {SwapFacet} from "./facets/SwapFacet.sol";
import {ValueFacet, ValueSingleFacet} from "./facets/ValueFacet.sol";
import {IBurveMultiValue} from "./interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "./interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "./facets/ValueTokenFacet.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {LockFacet} from "./facets/LockFacet.sol";
import {VaultFacet} from "./facets/VaultFacet.sol";
import {SimplexLib} from "./Simplex.sol";

error FunctionNotFound(bytes4 _functionSelector);

contract SimplexDiamond is IDiamond {
    constructor(
        BurveFacets memory facets,
        string memory name,
        string memory symbol
    ) {
        AdminLib.initOwner(msg.sender);
        SimplexLib.init(name, symbol, facets.adjustor, 0, 0);

        FacetCut[] memory cuts = new FacetCut[](15);

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
            bytes4[] memory adminSelectors = new bytes4[](4);
            adminSelectors[0] = BaseAdminFacet.transferOwnership.selector;
            adminSelectors[1] = BaseAdminFacet.acceptOwnership.selector;
            adminSelectors[2] = BaseAdminFacet.owner.selector;
            adminSelectors[3] = BaseAdminFacet.adminRights.selector;
            cuts[2] = FacetCut({
                facetAddress: address(new BaseAdminFacet()),
                action: FacetCutAction.Add,
                functionSelectors: adminSelectors
            });
        }

        {
            bytes4[] memory valueSelectors = new bytes4[](3);
            valueSelectors[0] = IBurveMultiValue.addValue.selector;
            valueSelectors[1] = IBurveMultiValue.removeValue.selector;
            valueSelectors[2] = IBurveMultiValue.collectEarnings.selector;

            cuts[3] = FacetCut({
                facetAddress: facets.valueFacet,
                action: FacetCutAction.Add,
                functionSelectors: valueSelectors
            });
        }

        {
            bytes4[] memory valueSelectors = new bytes4[](2);
            valueSelectors[0] = IBurveMultiValue.addValueSingle.selector;
            valueSelectors[1] = IBurveMultiValue.removeValueSingle.selector;

            cuts[4] = FacetCut({
                facetAddress: facets.valueSingleFacet,
                action: FacetCutAction.Add,
                functionSelectors: valueSelectors
            });
        }

        {
            bytes4[] memory valueSelectors = new bytes4[](1);
            valueSelectors[0] = IBurveMultiValue.addSingleForValue.selector;
            cuts[5] = FacetCut({
                facetAddress: facets.addTokenValueFacet,
                action: FacetCutAction.Add,
                functionSelectors: valueSelectors
            });
        }

        {
            bytes4[] memory valueSelectors = new bytes4[](1);
            valueSelectors[0] = IBurveMultiValue.removeSingleForValue.selector;
            cuts[6] = FacetCut({
                facetAddress: facets.removeTokenValueFacet,
                action: FacetCutAction.Add,
                functionSelectors: valueSelectors
            });
        }

        {
            bytes4[] memory valueSelectors = new bytes4[](1);
            valueSelectors[0] = IBurveMultiValue.queryValue.selector;

            cuts[7] = FacetCut({
                facetAddress: facets.queryValueFacet,
                action: FacetCutAction.Add,
                functionSelectors: valueSelectors
            });
        }

        {
            bytes4[] memory swapSelectors = new bytes4[](2);
            swapSelectors[0] = SwapFacet.swap.selector;
            swapSelectors[1] = SwapFacet.simSwap.selector;
            cuts[8] = FacetCut({
                facetAddress: facets.swapFacet,
                action: FacetCutAction.Add,
                functionSelectors: swapSelectors
            });
        }

        {
            bytes4[] memory simplexSelectors = new bytes4[](3);
            simplexSelectors[0] = IBurveMultiSimplex.addVertex.selector;
            simplexSelectors[1] = IBurveMultiSimplex.addClosure.selector;
            simplexSelectors[2] = IBurveMultiSimplex.withdraw.selector;

            cuts[9] = FacetCut({
                facetAddress: facets.simplexAdminFacet,
                action: FacetCutAction.Add,
                functionSelectors: simplexSelectors
            });
        }

        {
            bytes4[] memory simplexSelectors = new bytes4[](8);
            simplexSelectors[0] = IBurveMultiSimplex.setEX128.selector;
            simplexSelectors[1] = IBurveMultiSimplex.setAdjustor.selector;
            simplexSelectors[2] = IBurveMultiSimplex.setBGTExchanger.selector;
            simplexSelectors[3] = IBurveMultiSimplex.setInitTarget.selector;
            simplexSelectors[4] = IBurveMultiSimplex.setSearchParams.selector;
            simplexSelectors[5] = IBurveMultiSimplex.setName.selector;
            simplexSelectors[6] = IBurveMultiSimplex.setSimplexFees.selector;
            simplexSelectors[7] = IBurveMultiSimplex.setEdgeFee.selector;

            cuts[10] = FacetCut({
                facetAddress: facets.simplexSetFacet,
                action: FacetCutAction.Add,
                functionSelectors: simplexSelectors
            });
        }

        {
            bytes4[] memory simplexSelectors = new bytes4[](16);
            simplexSelectors[0] = IBurveMultiSimplex.getName.selector;
            simplexSelectors[1] = IBurveMultiSimplex.getClosureValue.selector;
            simplexSelectors[2] = IBurveMultiSimplex.getClosureFees.selector;
            simplexSelectors[3] = IBurveMultiSimplex.getSimplexFees.selector;
            simplexSelectors[4] = IBurveMultiSimplex.getEdgeFee.selector;
            simplexSelectors[5] = IBurveMultiSimplex.protocolEarnings.selector;
            simplexSelectors[6] = IBurveMultiSimplex.getTokens.selector;
            simplexSelectors[7] = IBurveMultiSimplex.getNumVertices.selector;
            simplexSelectors[8] = IBurveMultiSimplex.getIdx.selector;
            simplexSelectors[9] = IBurveMultiSimplex.getVertexId.selector;
            simplexSelectors[10] = IBurveMultiSimplex.getEsX128.selector;
            simplexSelectors[11] = IBurveMultiSimplex.getEX128.selector;
            simplexSelectors[12] = IBurveMultiSimplex.getAdjustor.selector;
            simplexSelectors[13] = IBurveMultiSimplex.getBGTExchanger.selector;
            simplexSelectors[14] = IBurveMultiSimplex.getInitTarget.selector;
            simplexSelectors[15] = IBurveMultiSimplex.getSearchParams.selector;

            cuts[11] = FacetCut({
                facetAddress: facets.simplexGetFacet,
                action: FacetCutAction.Add,
                functionSelectors: simplexSelectors
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

            cuts[12] = IDiamond.FacetCut({
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

            cuts[13] = IDiamond.FacetCut({
                facetAddress: facets.vaultFacet,
                action: IDiamond.FacetCutAction.Add,
                functionSelectors: selectors
            });
        }

        {
            bytes4[] memory selectors = new bytes4[](5);
            selectors[0] = ValueTokenFacet.balanceOf.selector;
            selectors[1] = ValueTokenFacet.transfer.selector;
            selectors[2] = ValueTokenFacet.allowance.selector;
            selectors[3] = ValueTokenFacet.approve.selector;
            selectors[4] = ValueTokenFacet.transferFrom.selector;

            cuts[14] = IDiamond.FacetCut({
                facetAddress: facets.valueTokenFacet,
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
