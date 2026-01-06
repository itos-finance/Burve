// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DiamondCutFacet} from "Commons/Diamond/facets/DiamondCutFacet.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {ValueFacet, ValueSingleFacet, AddTokenValueFacet, RemoveTokenValueFacet, QueryValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {SimplexAdminFacet, SimplexSetFacet, SimplexGetFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {LockFacet} from "../../src/multi/facets/LockFacet.sol";
import {VaultFacet} from "../../src/multi/facets/VaultFacet.sol";
import {ValueTokenFacet} from "../../src/multi/facets/ValueTokenFacet.sol";
import {BaseAdminFacet} from "Commons/Util/Admin.sol";
import {IBurveMultiValue} from "../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";

abstract contract FacetCutScript is Script {
    DiamondCutFacet public diamondCutFacet;

    function _setDiamondCutFacet(address diamondAddress) internal {
        diamondCutFacet = DiamondCutFacet(diamondAddress);
    }

    // ============ CORE FACET CUTTING FUNCTIONS ============

    /// Generic function to cut any facet with custom selectors
    function _cutFacet(
        address facetAddress,
        bytes4[] memory selectors,
        IDiamond.FacetCutAction action
    ) internal {
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);

        cuts[0] = IDiamond.FacetCut({
            facetAddress: facetAddress,
            action: action,
            functionSelectors: selectors
        });

        diamondCutFacet.diamondCut(cuts, address(0), "");
        console2.log("Cut facet at address:", facetAddress);
    }

    // ============ DEPLOY AND CUT FUNCTIONS ============

    /// Deploy and cut ValueFacet (addValue, removeValue, collectEarnings)
    function _deployAndCutValueFacet() internal returns (address) {
        ValueFacet newFacet = new ValueFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = IBurveMultiValue.addValue.selector;
        selectors[1] = IBurveMultiValue.removeValue.selector;
        selectors[2] = IBurveMultiValue.collectEarnings.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Replace);
        console2.log("Deployed and cut ValueFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut ValueSingleFacet (addValueSingle, removeValueSingle)
    function _deployAndCutValueSingleFacet() internal returns (address) {
        ValueSingleFacet newFacet = new ValueSingleFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IBurveMultiValue.addValueSingle.selector;
        selectors[1] = IBurveMultiValue.removeValueSingle.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut ValueSingleFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut AddTokenValueFacet (addSingleForValue)
    function _deployAndCutAddTokenValueFacet() internal returns (address) {
        AddTokenValueFacet newFacet = new AddTokenValueFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IBurveMultiValue.addSingleForValue.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut AddTokenValueFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut RemoveTokenValueFacet (removeSingleForValue)
    function _deployAndCutRemoveTokenValueFacet() internal returns (address) {
        RemoveTokenValueFacet newFacet = new RemoveTokenValueFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IBurveMultiValue.removeSingleForValue.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log(
            "Deployed and cut RemoveTokenValueFacet at:",
            facetAddress
        );
        return facetAddress;
    }

    /// Deploy and cut QueryValueFacet (queryValue)
    function _deployAndCutQueryValueFacet() internal returns (address) {
        QueryValueFacet newFacet = new QueryValueFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IBurveMultiValue.queryValue.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut QueryValueFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut SwapFacet (swap, simSwap)
    function _deployAndCutSwapFacet() internal returns (address) {
        SwapFacet newFacet = new SwapFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = SwapFacet.swap.selector;
        selectors[1] = SwapFacet.simSwap.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut SwapFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut SimplexAdminFacet (addVertex, addClosure, withdraw)
    function _deployAndCutSimplexAdminFacet() internal returns (address) {
        SimplexAdminFacet newFacet = new SimplexAdminFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = IBurveMultiSimplex.addVertex.selector;
        selectors[1] = IBurveMultiSimplex.addClosure.selector;
        selectors[2] = IBurveMultiSimplex.withdraw.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut SimplexAdminFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut SimplexSetFacet (set functions)
    function _deployAndCutSimplexSetFacet() internal returns (address) {
        SimplexSetFacet newFacet = new SimplexSetFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = IBurveMultiSimplex.setEX128.selector;
        selectors[1] = IBurveMultiSimplex.setAdjustor.selector;
        selectors[2] = IBurveMultiSimplex.setBGTExchanger.selector;
        selectors[3] = IBurveMultiSimplex.setInitTarget.selector;
        selectors[4] = IBurveMultiSimplex.setSearchParams.selector;
        selectors[5] = IBurveMultiSimplex.setName.selector;
        selectors[6] = IBurveMultiSimplex.setSimplexFees.selector;
        selectors[7] = IBurveMultiSimplex.setEdgeFee.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut SimplexSetFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut SimplexGetFacet (get functions)
    function _deployAndCutSimplexGetFacet() internal returns (address) {
        SimplexGetFacet newFacet = new SimplexGetFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](16);
        selectors[0] = IBurveMultiSimplex.getName.selector;
        selectors[1] = IBurveMultiSimplex.getClosureValue.selector;
        selectors[2] = IBurveMultiSimplex.getClosureFees.selector;
        selectors[3] = IBurveMultiSimplex.getSimplexFees.selector;
        selectors[4] = IBurveMultiSimplex.getEdgeFee.selector;
        selectors[5] = IBurveMultiSimplex.protocolEarnings.selector;
        selectors[6] = IBurveMultiSimplex.getTokens.selector;
        selectors[7] = IBurveMultiSimplex.getNumVertices.selector;
        selectors[8] = IBurveMultiSimplex.getIdx.selector;
        selectors[9] = IBurveMultiSimplex.getVertexId.selector;
        selectors[10] = IBurveMultiSimplex.getEsX128.selector;
        selectors[11] = IBurveMultiSimplex.getEX128.selector;
        selectors[12] = IBurveMultiSimplex.getAdjustor.selector;
        selectors[13] = IBurveMultiSimplex.getBGTExchanger.selector;
        selectors[14] = IBurveMultiSimplex.getInitTarget.selector;
        selectors[15] = IBurveMultiSimplex.getSearchParams.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut SimplexGetFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut LockFacet (lock, unlock, isLocked, addLocker, addUnlocker, removeLocker, removeUnlocker)
    function _deployAndCutLockFacet() internal returns (address) {
        LockFacet newFacet = new LockFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = LockFacet.lock.selector;
        selectors[1] = LockFacet.unlock.selector;
        selectors[2] = LockFacet.isLocked.selector;
        selectors[3] = LockFacet.addLocker.selector;
        selectors[4] = LockFacet.addUnlocker.selector;
        selectors[5] = LockFacet.removeLocker.selector;
        selectors[6] = LockFacet.removeUnlocker.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut LockFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut VaultFacet (addVault, acceptVault, vetoVault, removeVault, hotSwap)
    function _deployAndCutVaultFacet() internal returns (address) {
        VaultFacet newFacet = new VaultFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = VaultFacet.addVault.selector;
        selectors[1] = VaultFacet.acceptVault.selector;
        selectors[2] = VaultFacet.vetoVault.selector;
        selectors[3] = VaultFacet.removeVault.selector;
        selectors[4] = VaultFacet.hotSwap.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut VaultFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut ValueTokenFacet (balanceOf, transfer, allowance, approve, transferFrom)
    function _deployAndCutValueTokenFacet() internal returns (address) {
        ValueTokenFacet newFacet = new ValueTokenFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = ValueTokenFacet.balanceOf.selector;
        selectors[1] = ValueTokenFacet.transfer.selector;
        selectors[2] = ValueTokenFacet.allowance.selector;
        selectors[3] = ValueTokenFacet.approve.selector;
        selectors[4] = ValueTokenFacet.transferFrom.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut ValueTokenFacet at:", facetAddress);
        return facetAddress;
    }

    /// Deploy and cut BaseAdminFacet (transferOwnership, acceptOwnership, owner, adminRights)
    function _deployAndCutAdminFacet() internal returns (address) {
        BaseAdminFacet newFacet = new BaseAdminFacet();
        address facetAddress = address(newFacet);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = BaseAdminFacet.transferOwnership.selector;
        selectors[1] = BaseAdminFacet.acceptOwnership.selector;
        selectors[2] = BaseAdminFacet.owner.selector;
        selectors[3] = BaseAdminFacet.adminRights.selector;

        _cutFacet(facetAddress, selectors, IDiamond.FacetCutAction.Add);
        console2.log("Deployed and cut BaseAdminFacet at:", facetAddress);
        return facetAddress;
    }

    // ============ CONVENIENCE FUNCTIONS ============

    /// Deploy and cut all value-related facets at once
    function _deployAndCutAllValueFacets()
        internal
        returns (
            address valueFacetAddr,
            address valueSingleFacetAddr,
            address addTokenValueFacetAddr,
            address removeTokenValueFacetAddr,
            address queryValueFacetAddr
        )
    {
        console2.log("Deploying and cutting all value facets...");
        valueFacetAddr = _deployAndCutValueFacet();
        valueSingleFacetAddr = _deployAndCutValueSingleFacet();
        addTokenValueFacetAddr = _deployAndCutAddTokenValueFacet();
        removeTokenValueFacetAddr = _deployAndCutRemoveTokenValueFacet();
        queryValueFacetAddr = _deployAndCutQueryValueFacet();
        console2.log("All value facets deployed and cut successfully");
    }

    /// Deploy and cut all simplex-related facets at once
    function _deployAndCutAllSimplexFacets()
        internal
        returns (
            address simplexAdminFacetAddr,
            address simplexSetFacetAddr,
            address simplexGetFacetAddr
        )
    {
        console2.log("Deploying and cutting all simplex facets...");
        simplexAdminFacetAddr = _deployAndCutSimplexAdminFacet();
        simplexSetFacetAddr = _deployAndCutSimplexSetFacet();
        simplexGetFacetAddr = _deployAndCutSimplexGetFacet();
        console2.log("All simplex facets deployed and cut successfully");
    }

    /// Deploy and cut all core facets at once
    function _deployAndCutAllCoreFacets()
        internal
        returns (
            address swapFacetAddr,
            address lockFacetAddr,
            address vaultFacetAddr,
            address valueTokenFacetAddr,
            address adminFacetAddr
        )
    {
        console2.log("Deploying and cutting all core facets...");
        swapFacetAddr = _deployAndCutSwapFacet();
        lockFacetAddr = _deployAndCutLockFacet();
        vaultFacetAddr = _deployAndCutVaultFacet();
        valueTokenFacetAddr = _deployAndCutValueTokenFacet();
        adminFacetAddr = _deployAndCutAdminFacet();
        console2.log("All core facets deployed and cut successfully");
    }

    /// Deploy and cut all facets at once
    function _deployAndCutAllFacets()
        internal
        returns (
            address valueFacetAddr,
            address valueSingleFacetAddr,
            address addTokenValueFacetAddr,
            address removeTokenValueFacetAddr,
            address queryValueFacetAddr,
            address swapFacetAddr,
            address simplexAdminFacetAddr,
            address simplexSetFacetAddr,
            address simplexGetFacetAddr,
            address lockFacetAddr,
            address vaultFacetAddr,
            address valueTokenFacetAddr,
            address adminFacetAddr
        )
    {
        console2.log("Deploying and cutting all facets...");

        // Value facets
        (
            valueFacetAddr,
            valueSingleFacetAddr,
            addTokenValueFacetAddr,
            removeTokenValueFacetAddr,
            queryValueFacetAddr
        ) = _deployAndCutAllValueFacets();

        // Core facets
        (
            swapFacetAddr,
            lockFacetAddr,
            vaultFacetAddr,
            valueTokenFacetAddr,
            adminFacetAddr
        ) = _deployAndCutAllCoreFacets();

        // Simplex facets
        (
            simplexAdminFacetAddr,
            simplexSetFacetAddr,
            simplexGetFacetAddr
        ) = _deployAndCutAllSimplexFacets();

        console2.log("All facets deployed and cut successfully");
    }

    // ============ LEGACY FUNCTIONS (for backward compatibility) ============

    /// Cut existing facet with custom selectors (legacy function)
    function _cutFacetWithSelectors(
        address facetAddress,
        bytes4[] memory selectors,
        IDiamond.FacetCutAction action
    ) internal {
        _cutFacet(facetAddress, selectors, action);
    }
}
