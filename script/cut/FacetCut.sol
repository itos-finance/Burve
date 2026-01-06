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
    address constant FACET =
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
            facetAddress: FACET,
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

    /////////////////////////////////////////////////
    //                Selectors                    //
    /////////////////////////////////////////////////

    // function _getSimplexAdminSelectors()
    //     internal
    //     pure
    //     returns (bytes4[] memory)
    // {
    //     bytes4[] memory selectors = new bytes4[](3);
    //     selectors[0] = SimplexAdminFacet.addVertex.selector;
    //     selectors[1] = SimplexAdminFacet.addClosure.selector;
    //     selectors[2] = SimplexAdminFacet.withdraw.selector;
    //     return selectors;
    // }

    // function _getSimplexSetSelectors() internal pure returns (bytes4[] memory) {
    //     bytes4[] memory selectors = new bytes4[](8);
    //     selectors[0] = SimplexSetFacet.setEX128.selector;
    //     selectors[1] = SimplexSetFacet.setAdjustor.selector;
    //     selectors[2] = SimplexSetFacet.setBGTExchanger.selector;
    //     selectors[3] = SimplexSetFacet.setInitTarget.selector;
    //     selectors[4] = SimplexSetFacet.setSearchParams.selector;
    //     selectors[5] = SimplexSetFacet.setName.selector;
    //     selectors[6] = SimplexSetFacet.setSimplexFees.selector;
    //     selectors[7] = SimplexSetFacet.setEdgeFee.selector;
    //     return selectors;
    // }

    // function _getSimplexGetSelectors() internal pure returns (bytes4[] memory) {
    //     bytes4[] memory selectors = new bytes4[](12);
    //     selectors[0] = SimplexGetFacet.getName.selector;
    //     selectors[1] = SimplexGetFacet.getClosureValue.selector;
    //     selectors[2] = SimplexGetFacet.getClosureFees.selector;
    //     selectors[3] = SimplexGetFacet.getSimplexFees.selector;
    //     selectors[4] = SimplexGetFacet.getEdgeFee.selector;
    //     selectors[5] = SimplexGetFacet.protocolEarnings.selector;
    //     selectors[6] = SimplexGetFacet.getTokens.selector;
    //     selectors[7] = SimplexGetFacet.getNumVertices.selector;
    //     selectors[8] = SimplexGetFacet.getIdx.selector;
    //     selectors[9] = SimplexGetFacet.getVertexId.selector;
    //     selectors[10] = SimplexGetFacet.getSearchParams.selector;
    //     selectors[11] = SimplexGetFacet.getEsX128.selector;
    //     return selectors;
    // }

    // function _getValueSelectors() internal pure returns (bytes4[] memory) {
    //     bytes4[] memory selectors = new bytes4[](3);
    //     selectors[0] = ValueFacet.addValue.selector;
    //     selectors[1] = ValueFacet.removeValue.selector;
    //     selectors[2] = ValueFacet.collectEarnings.selector;
    //     return selectors;
    // }

    // function _getValueSingleSelectors()
    //     internal
    //     pure
    //     returns (bytes4[] memory)
    // {
    //     bytes4[] memory selectors = new bytes4[](2);
    //     selectors[0] = ValueSingleFacet.addValueSingle.selector;
    //     selectors[1] = ValueSingleFacet.removeValueSingle.selector;
    //     return selectors;
    // }

    // function _getAddTokenValueSelectors()
    //     internal
    //     pure
    //     returns (bytes4[] memory)
    // {
    //     bytes4[] memory selectors = new bytes4[](1);
    //     selectors[0] = AddTokenValueFacet.addSingleForValue.selector;
    //     return selectors;
    // }

    // function _getRemoveTokenValueSelectors()
    //     internal
    //     pure
    //     returns (bytes4[] memory)
    // {
    //     bytes4[] memory selectors = new bytes4[](1);
    //     selectors[0] = RemoveTokenValueFacet.removeSingleForValue.selector;
    //     return selectors;
    // }

    // function _getQueryValueSelectors() internal pure returns (bytes4[] memory) {
    //     bytes4[] memory selectors = new bytes4[](1);
    //     selectors[0] = QueryValueFacet.queryValue.selector;
    //     return selectors;
    // }

    // function _getSwapSelectors() internal pure returns (bytes4[] memory) {
    //     bytes4[] memory selectors = new bytes4[](2);
    //     selectors[0] = SwapFacet.swap.selector;
    //     selectors[1] = SwapFacet.simSwap.selector;
    //     return selectors;
    // }

    // function _getValueTokenSelectors() internal pure returns (bytes4[] memory) {
    //     bytes4[] memory selectors = new bytes4[](4);
    //     selectors[0] = ValueTokenFacet.balanceOf.selector;
    //     selectors[1] = ValueTokenFacet.transfer.selector;
    //     selectors[2] = ValueTokenFacet.allowance.selector;
    //     selectors[3] = ValueTokenFacet.approve.selector;
    //     return selectors;
    // }

    // function _getLockSelectors() internal pure returns (bytes4[] memory) {
    //     bytes4[] memory selectors = new bytes4[](7);
    //     selectors[0] = LockFacet.lock.selector;
    //     selectors[1] = LockFacet.unlock.selector;
    //     selectors[2] = LockFacet.isLocked.selector;
    //     selectors[3] = LockFacet.addLocker.selector;
    //     selectors[4] = LockFacet.removeLocker.selector;
    //     selectors[5] = LockFacet.addUnlocker.selector;
    //     selectors[6] = LockFacet.removeUnlocker.selector;
    //     return selectors;
    // }

    // function _getVaultSelectors() internal pure returns (bytes4[] memory) {
    //     bytes4[] memory selectors = new bytes4[](7);
    //     selectors[0] = VaultFacet.viewVaults.selector;
    //     selectors[1] = VaultFacet.addVault.selector;
    //     selectors[2] = VaultFacet.acceptVault.selector;
    //     selectors[3] = VaultFacet.vetoVault.selector;
    //     selectors[4] = VaultFacet.removeVault.selector;
    //     selectors[5] = VaultFacet.transferBalance.selector;
    //     selectors[6] = VaultFacet.hotSwap.selector;
    //     return selectors;
    // }
}
