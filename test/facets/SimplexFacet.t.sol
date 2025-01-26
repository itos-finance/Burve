// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BurveDeploymentLib} from "../../src/BurveDeploymentLib.sol";
import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {EdgeFacet} from "../../src/multi/facets/EdgeFacet.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {VaultType} from "../../src/multi/VaultProxy.sol";
import {Store} from "../../src/multi/Store.sol";
import {VertexId, newVertexId} from "../../src/multi/Vertex.sol";
import {TokenRegLib} from "../../src/multi/Token.sol";
import {Edge} from "../../src/multi/Edge.sol";

contract SimplexFacetTest is Test {
    SimplexDiamond public diamond;
    EdgeFacet public edgeFacet;
    SimplexFacet public simplexFacet;

    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20 public token2;

    address public owner = makeAddr("owner");
    address public nonOwner = makeAddr("nonOwner");

    event VertexAdded(
        address indexed token,
        address vault,
        VaultType vaultType
    );
    event EdgeUpdated(
        address indexed token0,
        address indexed token1,
        uint256 amplitude,
        int24 lowTick,
        int24 highTick
    );

    function setUp() public {
        vm.startPrank(owner);

        // Deploy the diamond and facets
        (
            address liqFacetAddr,
            address simplexFacetAddr,
            address swapFacetAddr
        ) = BurveDeploymentLib.deployFacets();

        diamond = new SimplexDiamond(
            liqFacetAddr,
            simplexFacetAddr,
            swapFacetAddr
        );

        edgeFacet = EdgeFacet(address(diamond));
        simplexFacet = SimplexFacet(address(diamond));

        // Setup test tokens
        token0 = new MockERC20("Test Token 0", "TEST0", 18);
        token1 = new MockERC20("Test Token 1", "TEST1", 18);
        token2 = new MockERC20("Test Token 2", "TEST2", 18);

        vm.stopPrank();
    }

    function testAddVertex() public {
        vm.startPrank(owner);

        // Add first vertex
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.UnImplemented
        );

        // Add second vertex
        simplexFacet.addVertex(
            address(token1),
            address(0),
            VaultType.UnImplemented
        );

        vm.stopPrank();
    }

    function testAddVertexRevertsForNonOwner() public {
        vm.startPrank(nonOwner);

        vm.expectRevert(); // Should revert for non-owner
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.UnImplemented
        );

        vm.stopPrank();
    }

    function testAddVertexRevertsForDuplicate() public {
        vm.startPrank(owner);

        // Add vertex first time
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.UnImplemented
        );

        // Try to add same vertex again
        vm.expectRevert(); // Should revert for duplicate vertex
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.UnImplemented
        );

        vm.stopPrank();
    }

    function testAddMultipleVertices() public {
        vm.startPrank(owner);

        // Add multiple vertices
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.UnImplemented
        );
        simplexFacet.addVertex(
            address(token1),
            address(0),
            VaultType.UnImplemented
        );
        simplexFacet.addVertex(
            address(token2),
            address(0),
            VaultType.UnImplemented
        );

        // Setup edges between vertices
        edgeFacet.setEdge(
            address(token0),
            address(token1),
            1e18,
            -887272,
            887272
        );
        edgeFacet.setEdge(
            address(token1),
            address(token2),
            1e18,
            -887272,
            887272
        );
        edgeFacet.setEdge(
            address(token0),
            address(token2),
            1e18,
            -887272,
            887272
        );

        vm.stopPrank();
    }

    function testAddVertexWithCustomVault() public {
        address mockVault = makeAddr("mockVault");

        vm.startPrank(owner);

        // Add vertex with custom vault
        simplexFacet.addVertex(
            address(token0),
            mockVault,
            VaultType.UnImplemented
        );

        vm.stopPrank();
    }

    function testAddVertexWithInvalidVaultType() public {
        vm.startPrank(owner);

        // Try to add vertex with invalid vault type
        vm.expectRevert();
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.E4626 // Use E4626 as invalid type
        );

        vm.stopPrank();
    }

    function testVertexInitialization() public {
        vm.startPrank(owner);

        // Expect vertex added event
        vm.expectEmit(true, true, true, true);
        emit VertexAdded(address(token0), address(0), VaultType.UnImplemented);

        // Add vertex
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.UnImplemented
        );

        // Get vertex info from Store
        VertexId vid = newVertexId(TokenRegLib.getIdx(address(token0)));
        VaultType vaultType = Store.vaults().vTypes[vid];

        // Verify vertex state
        assertTrue(
            vaultType == VaultType.UnImplemented,
            "Incorrect vault type"
        );

        vm.stopPrank();
    }

    function testVertexConnections() public {
        vm.startPrank(owner);

        // Add vertices
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.UnImplemented
        );
        simplexFacet.addVertex(
            address(token1),
            address(0),
            VaultType.UnImplemented
        );

        // Expect edge updated event
        vm.expectEmit(true, true, true, true);
        emit EdgeUpdated(
            address(token0),
            address(token1),
            1e18,
            -887272,
            887272
        );

        // Setup edge
        edgeFacet.setEdge(
            address(token0),
            address(token1),
            1e18,
            -887272,
            887272
        );

        // Verify edge exists and parameters
        Edge storage edge = Store.edge(address(token0), address(token1));
        assertEq(edge.amplitude, 1e18, "Incorrect amplitude");
        assertEq(edge.lowTick, -887272, "Incorrect lowTick");
        assertEq(edge.highTick, 887272, "Incorrect highTick");

        vm.stopPrank();
    }

    function testComplexVertexNetwork() public {
        vm.startPrank(owner);

        // Add all vertices
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.UnImplemented
        );
        simplexFacet.addVertex(
            address(token1),
            address(0),
            VaultType.UnImplemented
        );
        simplexFacet.addVertex(
            address(token2),
            address(0),
            VaultType.UnImplemented
        );

        // Setup all edges
        edgeFacet.setEdge(
            address(token0),
            address(token1),
            1e18,
            -887272,
            887272
        );
        edgeFacet.setEdge(
            address(token1),
            address(token2),
            1e18,
            -887272,
            887272
        );
        edgeFacet.setEdge(
            address(token0),
            address(token2),
            1e18,
            -887272,
            887272
        );

        // Verify network structure through edge parameters
        Edge storage edge01 = Store.edge(address(token0), address(token1));
        Edge storage edge12 = Store.edge(address(token1), address(token2));
        Edge storage edge02 = Store.edge(address(token0), address(token2));

        assertEq(
            edge01.amplitude,
            1e18,
            "Edge01 should have correct amplitude"
        );
        assertEq(
            edge12.amplitude,
            1e18,
            "Edge12 should have correct amplitude"
        );
        assertEq(
            edge02.amplitude,
            1e18,
            "Edge02 should have correct amplitude"
        );

        vm.stopPrank();
    }
}
