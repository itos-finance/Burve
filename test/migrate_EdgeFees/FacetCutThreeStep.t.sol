// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {SimplexDiamond as BurveDiamond} from "../../src/multi/Diamond.sol";
import {SimplexSetFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {SearchParams} from "../../src/multi/Value.sol";
import {InitLib, BurveFacets} from "../../src/multi/InitLib.sol";
import {FacetCut} from "../../script/migrate_EdgeFees/FacetCut.s.sol";

contract FacetCutThreeStepTest is Test {
    // Core contracts
    BurveDiamond public diamond;
    IBurveMultiSimplex public simplexFacet;
    SimplexSetFacet public simplexSetFacet;
    FacetCut public facetCut;

    // Test owner
    address public owner;

    function setUp() public {
        // Create a test owner
        owner = makeAddr("owner");
        vm.deal(owner, 10 ether);

        // Deploy a fresh diamond for testing
        vm.startPrank(owner);
        BurveFacets memory facets = InitLib.deployFacets();
        diamond = new BurveDiamond(facets, "Test Value Token", "TVT");
        vm.stopPrank();

        // Initialize contracts
        simplexFacet = IBurveMultiSimplex(address(diamond));
        simplexSetFacet = SimplexSetFacet(address(diamond));
    }

    function testFacetCutThreeStepProcess() public {
        // Deploy the FacetCut contract with the diamond address
        facetCut = new FacetCut(address(diamond));
        console2.log("FacetCut contract deployed at:", address(facetCut));

        // First, transfer ownership of the diamond to the FacetCut contract
        vm.prank(owner);
        // We need to call the diamond's transferOwnership function directly
        // Since we don't have a direct interface, we'll use a low-level call
        (bool success, ) = address(diamond).call(
            abi.encodeWithSignature(
                "transferOwnership(address)",
                address(facetCut)
            )
        );
        require(success, "Failed to transfer ownership to FacetCut contract");

        // Step 1: Accept ownership
        facetCut.acceptOwnership();
        console2.log("Step 1: Ownership accepted");

        // Step 2: Perform the facet cut
        facetCut.performFacetCut();
        console2.log("Step 2: Facet cut performed successfully");

        // Step 3: Transfer ownership back
        facetCut.transferOwnership();
        console2.log("Step 3: Ownership transferred back to multisig");

        // Test that the new facet functions work
        _testSimplexSetFacetFunctions();
    }

    function _testSimplexSetFacetFunctions() internal {
        // Test setting search params
        SearchParams memory newParams = SearchParams({
            maxIter: 50,
            deMinimusX128: 1000,
            targetSlippageX128: 5000
        });

        vm.prank(owner);
        simplexSetFacet.setSearchParams(newParams);

        // Verify the search params were set
        SearchParams memory retrievedParams = simplexFacet.getSearchParams();
        assertEq(retrievedParams.maxIter, 50);
        assertEq(retrievedParams.deMinimusX128, 1000);
        assertEq(retrievedParams.targetSlippageX128, 5000);

        console2.log("Search params set and verified successfully");

        // Test setting simplex fees
        uint128 newDefaultEdgeFee = 136112946768375385385349842972707284; // 4 bps
        uint128 newProtocolTake = 27222589353675077077069968594541456916; // 8%

        vm.prank(owner);
        simplexSetFacet.setSimplexFees(newDefaultEdgeFee, newProtocolTake);

        // Verify the fees were set
        (uint128 defaultEdgeFee, uint128 protocolTake) = simplexFacet
            .getSimplexFees();
        assertEq(defaultEdgeFee, newDefaultEdgeFee);
        assertEq(protocolTake, newProtocolTake);

        console2.log("Simplex fees set and verified successfully");

        // Test setting name and symbol
        string memory newName = "New Value Token";
        string memory newSymbol = "NVT";

        vm.prank(owner);
        simplexSetFacet.setName(newName, newSymbol);

        // Verify the name and symbol were set
        (string memory name, string memory symbol) = simplexFacet.getName();
        assertEq(name, newName);
        assertEq(symbol, newSymbol);

        console2.log("Name and symbol set and verified successfully");

        console2.log(
            "All SimplexSetFacet functions working correctly after upgrade"
        );
    }

    function testFacetCutRevertsWhenNotOwner() public {
        // Deploy the FacetCut contract
        facetCut = new FacetCut(address(diamond));

        // Try to accept ownership as non-owner (should revert)
        vm.prank(address(0x123)); // Random address
        vm.expectRevert();
        facetCut.acceptOwnership();
    }

    function testFacetCutRevertsWhenNotOwnerForFacetCut() public {
        // Deploy the FacetCut contract
        facetCut = new FacetCut(address(diamond));

        // Transfer ownership to FacetCut contract
        vm.prank(owner);
        (bool success, ) = address(diamond).call(
            abi.encodeWithSignature(
                "transferOwnership(address)",
                address(facetCut)
            )
        );
        require(success, "Failed to transfer ownership");

        // Accept ownership first
        facetCut.acceptOwnership();

        // Try to perform facet cut as non-owner (should revert)
        vm.prank(address(0x123)); // Random address
        vm.expectRevert();
        facetCut.performFacetCut();
    }

    function testFacetCutRevertsWhenNotOwnerForTransfer() public {
        // Deploy the FacetCut contract
        facetCut = new FacetCut(address(diamond));

        // Transfer ownership to FacetCut contract
        vm.prank(owner);
        (bool success, ) = address(diamond).call(
            abi.encodeWithSignature(
                "transferOwnership(address)",
                address(facetCut)
            )
        );
        require(success, "Failed to transfer ownership");

        // Accept ownership first
        facetCut.acceptOwnership();

        // Try to transfer ownership as non-owner (should revert)
        vm.prank(address(0x123)); // Random address
        vm.expectRevert();
        facetCut.transferOwnership();
    }
}
