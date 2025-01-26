// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BurveDeploymentLib} from "../../src/BurveDeploymentLib.sol";
import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {EdgeFacet} from "../../src/multi/facets/EdgeFacet.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {StorageFacet} from "../mocks/StorageFacet.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {VaultType, VaultLib} from "../../src/multi/VaultProxy.sol";

import {TokenRegistryImpl} from "../../src/multi/Token.sol";

import {Store} from "../../src/multi/Store.sol";
import {VertexId, newVertexId} from "../../src/multi/Vertex.sol";
import {TokenRegLib} from "../../src/multi/Token.sol";
import {Edge} from "../../src/multi/Edge.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";

contract SimplexFacetTest is Test {
    SimplexDiamond public diamond;
    EdgeFacet public edgeFacet;
    SimplexFacet public simplexFacet;
    StorageFacet public storageFacet;

    MockERC20 public token0;
    MockERC20 public token1;
    MockERC4626 public mockVault0;
    MockERC4626 public mockVault1;

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
        storageFacet = StorageFacet(address(diamond));

        // Setup test tokens
        token0 = new MockERC20("Test Token 0", "TEST0", 18);
        token1 = new MockERC20("Test Token 1", "TEST1", 18);

        mockVault0 = new MockERC4626(token0, "Mock Vault 0", "MVLT0");
        mockVault1 = new MockERC4626(token1, "Mock Vault 1", "MVLT1");

        vm.stopPrank();
    }

    function testAddVertex() public {
        vm.startPrank(owner);

        // Add first vertex
        simplexFacet.addVertex(
            address(token0),
            address(mockVault0),
            VaultType.E4626
        );

        // Add second vertex
        simplexFacet.addVertex(
            address(token1),
            address(mockVault1),
            VaultType.E4626
        );

        vm.stopPrank();
    }

    function testAddVertexRevertUnimplemented() public {
        vm.startPrank(owner);

        // Add first vertex
        vm.expectRevert(
            abi.encodeWithSelector(VaultLib.VaultTypeNotRecognized.selector, 0)
        );
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.UnImplemented
        );

        // Add second vertex
        vm.expectRevert(
            abi.encodeWithSelector(VaultLib.VaultTypeNotRecognized.selector, 0)
        );
        simplexFacet.addVertex(
            address(token1),
            address(0),
            VaultType.UnImplemented
        );

        vm.stopPrank();
    }

    function testAddVertexRevertNonOwner() public {
        vm.startPrank(nonOwner);

        vm.expectRevert();
        simplexFacet.addVertex(
            address(token0),
            address(mockVault0),
            VaultType.E4626
        );

        vm.stopPrank();
    }

    function testAddVertexRevertsForDuplicate() public {
        vm.startPrank(owner);

        // Add vertex first time
        simplexFacet.addVertex(
            address(token0),
            address(mockVault0),
            VaultType.E4626
        );

        // Try to add same vertex again
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenRegistryImpl.TokenAlreadyRegistered.selector,
                address(token0)
            )
        ); // Should revert for duplicate vertex
        simplexFacet.addVertex(
            address(token0),
            address(mockVault0),
            VaultType.E4626
        );

        vm.stopPrank();
    }
}
