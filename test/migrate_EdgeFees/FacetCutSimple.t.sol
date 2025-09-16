// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {IDiamondCut} from "Commons/Diamond/interfaces/IDiamondCut.sol";
import {SimplexDiamond as BurveDiamond} from "../../src/multi/Diamond.sol";
import {SimplexSetFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {SearchParams} from "../../src/multi/Value.sol";
import {InitLib, BurveFacets} from "../../src/multi/InitLib.sol";

contract FacetCutSimpleTest is Test {
    // Core contracts
    BurveDiamond public diamond;
    IBurveMultiSimplex public simplexFacet;
    SimplexSetFacet public simplexSetFacet;

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

    function testFacetCutSimplexSetFacet() public {
        // Deploy new SimplexSetFacet
        SimplexSetFacet newSimplexSetFacet = new SimplexSetFacet();
        console2.log(
            "New SimplexSetFacet deployed at:",
            address(newSimplexSetFacet)
        );

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
            facetAddress: address(newSimplexSetFacet),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: simplexSetSelectors
        });

        // Execute the diamond cut as owner
        vm.prank(owner);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        console2.log("SimplexSetFacet upgraded successfully");

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
        // Deploy new SimplexSetFacet
        SimplexSetFacet newSimplexSetFacet = new SimplexSetFacet();

        // Get function selectors
        bytes4[] memory simplexSetSelectors = new bytes4[](1);
        simplexSetSelectors[0] = SimplexSetFacet.setEX128.selector;

        // Create facet cut
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(newSimplexSetFacet),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: simplexSetSelectors
        });

        // Try to execute diamond cut as non-owner (should revert)
        vm.prank(address(0x123)); // Random address
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }
}
