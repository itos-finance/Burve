// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BurveDeploymentLib} from "../src/deployment/BurveDeployLib.sol";
import {SimplexDiamond} from "../src/multi/Diamond.sol";
import {EdgeFacet} from "../src/multi/facets/EdgeFacet.sol";
import {LiqFacet} from "../src/multi/facets/LiqFacet.sol";
import {SimplexFacet} from "../src/multi/facets/SimplexFacet.sol";
import {SwapFacet} from "../src/multi/facets/SwapFacet.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ClosureId, newClosureId} from "../src/multi/Closure.sol";
import {VaultType} from "../src/multi/VaultProxy.sol";

contract BurveTriPoolTest is Test {
    SimplexDiamond public diamond;
    LiqFacet public liqFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;

    // Test tokens
    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20 public token2;

    // Test accounts
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    // Common test amounts
    uint256 constant INITIAL_MINT_AMOUNT = 1000000e18;
    uint256 constant INITIAL_LIQUIDITY_AMOUNT = 100000e18;

    // Test closure IDs for each token pair
    uint16 public closure01Id; // token0-token1 pair
    uint16 public closure12Id; // token1-token2 pair
    uint16 public closure02Id; // token0-token2 pair

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

        // Cast the diamond address to the facet interfaces
        liqFacet = LiqFacet(address(diamond));
        simplexFacet = SimplexFacet(address(diamond));
        swapFacet = SwapFacet(address(diamond));

        // Setup test tokens
        _setupTestTokens();

        // Fund test accounts
        _fundTestAccounts();

        // Setup closures for each token pair
        _setupClosures();

        // Add vertices and edges
        _setupVerticesAndEdges();

        vm.stopPrank();
    }

    function _setupTestTokens() internal {
        // Deploy tokens with 18 decimals
        token0 = new MockERC20("Test Token 0", "TEST0", 18);
        token1 = new MockERC20("Test Token 1", "TEST1", 18);
        token2 = new MockERC20("Test Token 2", "TEST2", 18);

        // Sort tokens by address to ensure consistent ordering
        _sortTokens();
    }

    function _sortTokens() internal {
        // Bubble sort the tokens by address
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        if (address(token1) > address(token2)) {
            (token1, token2) = (token2, token1);
            if (address(token0) > address(token1)) {
                (token0, token1) = (token1, token0);
            }
        }
    }

    function _fundTestAccounts() internal {
        // Fund alice and bob with initial amounts
        token0.mint(alice, INITIAL_MINT_AMOUNT);
        token1.mint(alice, INITIAL_MINT_AMOUNT);
        token2.mint(alice, INITIAL_MINT_AMOUNT);
        token0.mint(bob, INITIAL_MINT_AMOUNT);
        token1.mint(bob, INITIAL_MINT_AMOUNT);
        token2.mint(bob, INITIAL_MINT_AMOUNT);

        // Approve diamond for all test accounts
        vm.startPrank(alice);
        token0.approve(address(diamond), type(uint256).max);
        token1.approve(address(diamond), type(uint256).max);
        token2.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token0.approve(address(diamond), type(uint256).max);
        token1.approve(address(diamond), type(uint256).max);
        token2.approve(address(diamond), type(uint256).max);
        vm.stopPrank();
    }

    function _setupClosures() internal {
        // Setup closure for token0-token1 pair
        address[] memory tokens01 = new address[](2);
        tokens01[0] = address(token0);
        tokens01[1] = address(token1);
        closure01Id = ClosureId.unwrap(newClosureId(tokens01));

        // Setup closure for token1-token2 pair
        address[] memory tokens12 = new address[](2);
        tokens12[0] = address(token1);
        tokens12[1] = address(token2);
        closure12Id = ClosureId.unwrap(newClosureId(tokens12));

        // Setup closure for token0-token2 pair
        address[] memory tokens02 = new address[](2);
        tokens02[0] = address(token0);
        tokens02[1] = address(token2);
        closure02Id = ClosureId.unwrap(newClosureId(tokens02));
    }

    function _setupVerticesAndEdges() internal {
        // Add vertices
        // @TODO use mock vaults when possible.
        simplexFacet.addVertex(address(token0), address(0), VaultType.E4626);
        simplexFacet.addVertex(address(token1), address(0), VaultType.E4626);
        simplexFacet.addVertex(address(token2), address(0), VaultType.E4626);

        // Setup edges between all pairs
        // Note: These values might need adjustment based on your requirements
        _setupEdge(token0, token1);
        _setupEdge(token1, token2);
        _setupEdge(token0, token2);
    }

    function _setupEdge(MockERC20 tokenA, MockERC20 tokenB) internal {
        EdgeFacet(address(diamond)).setEdge(
            address(tokenA),
            address(tokenB),
            1e18, // amplitude
            -46063, // lowTick (-46063 represents price of ~0.01)
            46063 // highTick (46063 represents price of ~100)
        );
    }

    // Helper function to provide liquidity to a specific pair
    function _provideLiquidity(
        address provider,
        MockERC20 tokenA,
        MockERC20 tokenB,
        uint256 amountA,
        uint256 amountB,
        uint16 closureId
    ) internal returns (uint256 sharesA, uint256 sharesB) {
        vm.startPrank(provider);

        sharesA = liqFacet.addLiq(
            provider,
            closureId,
            address(tokenA),
            uint128(amountA)
        );

        sharesB = liqFacet.addLiq(
            provider,
            closureId,
            address(tokenB),
            uint128(amountB)
        );

        vm.stopPrank();
    }

    function testTriangleSetup() public {
        // Provide liquidity to all pairs
        (uint256 shares01A, uint256 shares01B) = _provideLiquidity(
            alice,
            token0,
            token1,
            INITIAL_LIQUIDITY_AMOUNT,
            INITIAL_LIQUIDITY_AMOUNT,
            closure01Id
        );

        (uint256 shares12A, uint256 shares12B) = _provideLiquidity(
            alice,
            token1,
            token2,
            INITIAL_LIQUIDITY_AMOUNT,
            INITIAL_LIQUIDITY_AMOUNT,
            closure12Id
        );

        (uint256 shares02A, uint256 shares02B) = _provideLiquidity(
            alice,
            token0,
            token2,
            INITIAL_LIQUIDITY_AMOUNT,
            INITIAL_LIQUIDITY_AMOUNT,
            closure02Id
        );

        // Verify all shares were minted
        assertGt(
            shares01A *
                shares01B *
                shares12A *
                shares12B *
                shares02A *
                shares02B,
            0,
            "All shares should be non-zero"
        );
    }

    function testTriangleArbitrage() public {}

    function testMultiHopSwap() public {}
}
