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
import {InitLib} from "../../src/multi/InitLib.sol";

contract FacetCutTest is Test {
    // Core contracts
    BurveDiamond public diamond;
    IBurveMultiSimplex public simplexFacet;
    SimplexSetFacet public simplexSetFacet;

    // Test addresses
    address constant DIAMOND_ADDRESS =
        0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;
    address constant OWNER_ADDRESS = 0x9293f9FFC43F6fce06290285919541E963D87F51;

    function setUp() public {
        // For this test, we'll simulate the diamond contract
        // In a real scenario, you would fork from mainnet
        // Note: This is a simplified test - in practice you'd fork from mainnet
        vm.etch(
            DIAMOND_ADDRESS,
            address(new BurveDiamond(InitLib.deployFacets(), "Test", "TST"))
                .code
        );

        // Initialize contracts
        diamond = BurveDiamond(payable(DIAMOND_ADDRESS));
        simplexFacet = IBurveMultiSimplex(DIAMOND_ADDRESS);
        simplexSetFacet = SimplexSetFacet(DIAMOND_ADDRESS);
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
        vm.prank(OWNER_ADDRESS);
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

        vm.prank(OWNER_ADDRESS);
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

        vm.prank(OWNER_ADDRESS);
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

        vm.prank(OWNER_ADDRESS);
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
