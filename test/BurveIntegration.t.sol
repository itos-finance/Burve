// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BurveDeploymentLib} from "../src/deployment/BurveDeployLib.sol";
import {SimplexDiamond} from "../src/multi/Diamond.sol";
import {LiqFacet} from "../src/multi/facets/LiqFacet.sol";
import {SimplexFacet} from "../src/multi/facets/SimplexFacet.sol";
import {EdgeFacet} from "../src/multi/facets/EdgeFacet.sol";
import {SwapFacet} from "../src/multi/facets/SwapFacet.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ClosureId, newClosureId} from "../src/multi/Closure.sol";
import {VaultType} from "../src/multi/VaultProxy.sol";

contract BurveIntegrationTest is Test {
    SimplexDiamond public diamond;
    LiqFacet public liqFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;
    EdgeFacet public edgeFacet;

    // Test tokens
    MockERC20 public token0;
    MockERC20 public token1;

    // Test accounts
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    // Common test amounts
    uint256 constant INITIAL_MINT_AMOUNT = 1000000e18;
    uint256 constant INITIAL_LIQUIDITY_AMOUNT = 100000e18;

    // Test closure ID for token pair
    uint16 public closureId;

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
        edgeFacet = EdgeFacet(address(diamond));

        // Setup test tokens
        _setupTestTokens();

        // Fund test accounts
        _fundTestAccounts();

        // Setup closure for token pair
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        closureId = ClosureId.unwrap(newClosureId(tokens));

        // Add vertices to the simplex with empty vaults
        // TODO: switch to mock vaults.
        simplexFacet.addVertex(address(token0), address(0), VaultType.E4626);
        simplexFacet.addVertex(address(token1), address(0), VaultType.E4626);

        // Setup edge between tokens
        // Note: These values might need adjustment based on your requirements
        edgeFacet.setEdge(
            address(token0),
            address(token1),
            1e18, // amplitude
            -887272, // lowTick (-887272 represents price of ~0.01)
            887272 // highTick (887272 represents price of ~100)
        );

        vm.stopPrank();
    }

    function _setupTestTokens() internal {
        // Deploy tokens with 18 decimals
        token0 = new MockERC20("Test Token 0", "TEST0", 18);
        token1 = new MockERC20("Test Token 1", "TEST1", 18);

        // Ensure token0 address is less than token1 for consistent ordering
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
    }

    function _fundTestAccounts() internal {
        // Fund alice and bob with initial amounts
        token0.mint(alice, INITIAL_MINT_AMOUNT);
        token1.mint(alice, INITIAL_MINT_AMOUNT);
        token0.mint(bob, INITIAL_MINT_AMOUNT);
        token1.mint(bob, INITIAL_MINT_AMOUNT);

        // Approve diamond for all test accounts
        vm.startPrank(alice);
        token0.approve(address(diamond), type(uint256).max);
        token1.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token0.approve(address(diamond), type(uint256).max);
        token1.approve(address(diamond), type(uint256).max);
        vm.stopPrank();
    }

    // Helper function to provide liquidity
    function _provideLiquidity(
        address provider,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 shares0, uint256 shares1) {
        vm.startPrank(provider);

        // Add liquidity for both tokens
        shares0 = liqFacet.addLiq(
            provider,
            closureId,
            address(token0),
            uint128(amount0)
        );

        shares1 = liqFacet.addLiq(
            provider,
            closureId,
            address(token1),
            uint128(amount1)
        );

        vm.stopPrank();
    }

    function testMint() public {
        uint256 amount0 = INITIAL_LIQUIDITY_AMOUNT;
        uint256 amount1 = INITIAL_LIQUIDITY_AMOUNT;

        // Check initial balances
        uint256 aliceToken0Before = token0.balanceOf(alice);
        uint256 aliceToken1Before = token1.balanceOf(alice);

        // Provide initial liquidity
        (uint256 shares0, uint256 shares1) = _provideLiquidity(
            alice,
            amount0,
            amount1
        );

        // Verify shares were minted
        assertGt(shares0, 0, "Should have received shares for token0");
        assertGt(shares1, 0, "Should have received shares for token1");

        // Verify tokens were transferred
        assertEq(
            token0.balanceOf(alice),
            aliceToken0Before - amount0,
            "Incorrect token0 balance after mint"
        );
        assertEq(
            token1.balanceOf(alice),
            aliceToken1Before - amount1,
            "Incorrect token1 balance after mint"
        );

        // TODO: Add more assertions for pool state
    }

    function testBurn() public {
        // First provide liquidity
        uint256 amount0 = INITIAL_LIQUIDITY_AMOUNT;
        uint256 amount1 = INITIAL_LIQUIDITY_AMOUNT;
        (uint256 shares0, uint256 shares1) = _provideLiquidity(
            alice,
            amount0,
            amount1
        );

        // Check balances before burn
        uint256 aliceToken0Before = token0.balanceOf(alice);
        uint256 aliceToken1Before = token1.balanceOf(alice);

        // Remove all liquidity
        vm.startPrank(alice);
        liqFacet.removeLiq(alice, closureId, shares0);
        liqFacet.removeLiq(alice, closureId, shares1);
        vm.stopPrank();

        // Verify tokens were returned
        assertEq(
            token0.balanceOf(alice),
            aliceToken0Before + amount0,
            "Incorrect token0 balance after burn"
        );
        assertEq(
            token1.balanceOf(alice),
            aliceToken1Before + amount1,
            "Incorrect token1 balance after burn"
        );

        // TODO: Add more assertions for pool state
    }

    function testSwap() public {
        // First provide liquidity
        uint256 amount0 = INITIAL_LIQUIDITY_AMOUNT;
        uint256 amount1 = INITIAL_LIQUIDITY_AMOUNT;
        _provideLiquidity(alice, amount0, amount1);

        // Prepare for swap
        uint256 swapAmount = 1000e18;
        uint256 bobToken0Before = token0.balanceOf(bob);
        uint256 bobToken1Before = token1.balanceOf(bob);

        // Perform swap token0 -> token1
        vm.startPrank(bob);
        swapFacet.swap(
            bob, // recipient
            address(token0), // tokenIn
            address(token1), // tokenOut
            int256(swapAmount), // positive for exact input
            0 // no price limit for this test
        );
        vm.stopPrank();

        // Verify balances after swap
        assertEq(
            token0.balanceOf(bob),
            bobToken0Before - swapAmount,
            "Incorrect token0 balance after swap"
        );
        assertGt(
            token1.balanceOf(bob),
            bobToken1Before,
            "Should have received token1"
        );

        // Perform reverse swap token1 -> token0
        uint256 token1Received = token1.balanceOf(bob) - bobToken1Before;
        bobToken0Before = token0.balanceOf(bob);
        bobToken1Before = token1.balanceOf(bob);

        vm.startPrank(bob);
        swapFacet.swap(
            bob, // recipient
            address(token1), // tokenIn
            address(token0), // tokenOut
            int256(token1Received), // positive for exact input
            0 // no price limit for this test
        );
        vm.stopPrank();

        // Verify balances after reverse swap
        assertEq(
            token1.balanceOf(bob),
            bobToken1Before - token1Received,
            "Incorrect token1 balance after reverse swap"
        );
        assertGt(
            token0.balanceOf(bob),
            bobToken0Before,
            "Should have received token0"
        );

        // TODO: Add more assertions for pool state and price impact
    }
}
