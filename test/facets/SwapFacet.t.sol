// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BurveDeploymentLib} from "../../src/BurveDeploymentLib.sol";
import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {EdgeFacet} from "../../src/multi/facets/EdgeFacet.sol";
import {LiqFacet} from "../../src/multi/facets/LiqFacet.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ClosureId, newClosureId} from "../../src/multi/Closure.sol";
import {VaultType} from "../../src/multi/VaultProxy.sol";
import {Store} from "../../src/multi/Store.sol";
import {Edge} from "../../src/multi/Edge.sol";

contract SwapFacetTest is Test {
    SimplexDiamond public diamond;
    EdgeFacet public edgeFacet;
    LiqFacet public liqFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;

    MockERC20 public token0;
    MockERC20 public token1;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint16 public closureId;
    uint256 constant INITIAL_MINT_AMOUNT = 1000000e18;
    uint256 constant INITIAL_LIQUIDITY_AMOUNT = 100000e18;

    // Price impact thresholds
    uint256 constant SMALL_SWAP_IMPACT_THRESHOLD = 1e16; // 1%
    uint256 constant LARGE_SWAP_IMPACT_THRESHOLD = 1e17; // 10%

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
        liqFacet = LiqFacet(address(diamond));
        simplexFacet = SimplexFacet(address(diamond));
        swapFacet = SwapFacet(address(diamond));

        // Setup test tokens
        token0 = new MockERC20("Test Token 0", "TEST0", 18);
        token1 = new MockERC20("Test Token 1", "TEST1", 18);

        // Ensure token0 address is less than token1
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Add vertices
        simplexFacet.addVertex(address(token0), address(0), VaultType.E4626);
        simplexFacet.addVertex(address(token1), address(0), VaultType.E4626);

        // Setup closure
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        closureId = ClosureId.unwrap(simplexFacet.getClosureId(tokens));

        // Setup edge
        edgeFacet.setEdge(
            address(token0),
            address(token1),
            1e18,
            -887272,
            887272
        );

        vm.stopPrank();

        // Fund test accounts
        _fundTestAccounts();

        // Setup initial liquidity
        _setupInitialLiquidity();
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

    function _setupInitialLiquidity() internal {
        vm.startPrank(alice);
        liqFacet.addLiq(
            alice,
            closureId,
            address(token0),
            uint128(INITIAL_LIQUIDITY_AMOUNT)
        );
        liqFacet.addLiq(
            alice,
            closureId,
            address(token1),
            uint128(INITIAL_LIQUIDITY_AMOUNT)
        );
        vm.stopPrank();
    }

    function testExactInputSwap() public {
        uint256 swapAmount = 1000e18;
        uint256 bobToken0Before = token0.balanceOf(bob);
        uint256 bobToken1Before = token1.balanceOf(bob);

        vm.startPrank(bob);
        swapFacet.swap(
            bob, // recipient
            address(token0), // tokenIn
            address(token1), // tokenOut
            int256(swapAmount), // positive for exact input
            0 // no price limit
        );
        vm.stopPrank();

        // Verify token0 was taken
        assertEq(
            token0.balanceOf(bob),
            bobToken0Before - swapAmount,
            "Incorrect token0 balance after swap"
        );

        // Verify some token1 was received
        assertGt(
            token1.balanceOf(bob),
            bobToken1Before,
            "Should have received token1"
        );
    }

    function testExactOutputSwap() public {
        uint256 outputAmount = 1000e18;
        uint256 bobToken0Before = token0.balanceOf(bob);
        uint256 bobToken1Before = token1.balanceOf(bob);

        vm.startPrank(bob);
        swapFacet.swap(
            bob, // recipient
            address(token0), // tokenIn
            address(token1), // tokenOut
            -int256(outputAmount), // negative for exact output
            0 // no price limit
        );
        vm.stopPrank();

        // Verify exact token1 was received
        assertEq(
            token1.balanceOf(bob),
            bobToken1Before + outputAmount,
            "Should have received exact token1 amount"
        );

        // Verify some token0 was taken
        assertLt(
            token0.balanceOf(bob),
            bobToken0Before,
            "Should have spent token0"
        );
    }

    function testSwapWithPriceLimit() public {
        uint256 swapAmount = 1000e18;
        uint160 sqrtPriceLimit = 79228162514264337593543950336; // ~1:1 price

        // Get initial price from edge using actual balances
        Edge storage edge = Store.edge(address(token0), address(token1));
        uint256 balance0 = token0.balanceOf(address(diamond));
        uint256 balance1 = token1.balanceOf(address(diamond));
        uint256 priceX128Before = edge.getPriceX128(
            uint128(balance0),
            uint128(balance1)
        );

        vm.startPrank(bob);
        swapFacet.swap(
            bob,
            address(token0),
            address(token1),
            int256(swapAmount),
            sqrtPriceLimit
        );
        vm.stopPrank();

        // Get final price using updated balances
        balance0 = token0.balanceOf(address(diamond));
        balance1 = token1.balanceOf(address(diamond));
        uint256 priceX128After = Store
            .edge(address(token0), address(token1))
            .getPriceX128(uint128(balance0), uint128(balance1));

        // Verify price changed but didn't exceed limit
        assertGt(
            priceX128After,
            priceX128Before,
            "Price should increase for token0->token1 swap"
        );
        // Convert sqrtPriceLimit to priceX128 format for comparison
        uint256 priceLimit = (uint256(sqrtPriceLimit) *
            uint256(sqrtPriceLimit) *
            (1 << 128)) /
            (1 << 96) /
            (1 << 96);
        assertLe(priceX128After, priceLimit, "Price should not exceed limit");
    }

    function testSmallSwapPriceImpact() public {
        uint256 swapAmount = INITIAL_LIQUIDITY_AMOUNT / 100; // 1% of pool liquidity
        uint256 bobToken0Before = token0.balanceOf(bob);
        uint256 bobToken1Before = token1.balanceOf(bob);

        // Get initial price using actual balances
        Edge storage edge = Store.edge(address(token0), address(token1));
        uint256 balance0 = token0.balanceOf(address(diamond));
        uint256 balance1 = token1.balanceOf(address(diamond));
        uint256 priceX128Before = edge.getPriceX128(
            uint128(balance0),
            uint128(balance1)
        );

        vm.startPrank(bob);
        swapFacet.swap(
            bob,
            address(token0),
            address(token1),
            int256(swapAmount),
            0
        );
        vm.stopPrank();

        // Get final price using updated balances
        balance0 = token0.balanceOf(address(diamond));
        balance1 = token1.balanceOf(address(diamond));
        uint256 priceX128After = Store
            .edge(address(token0), address(token1))
            .getPriceX128(uint128(balance0), uint128(balance1));

        // Calculate price impact
        uint256 priceImpact = ((
            priceX128After > priceX128Before
                ? priceX128After - priceX128Before
                : priceX128Before - priceX128After
        ) * 1e18) / priceX128Before;

        assertLt(
            priceImpact,
            SMALL_SWAP_IMPACT_THRESHOLD,
            "Small swap should have minimal price impact"
        );

        // Verify output amount is close to input amount (minimal slippage)
        uint256 token1Received = token1.balanceOf(bob) - bobToken1Before;
        assertApproxEqRel(
            token1Received,
            swapAmount,
            SMALL_SWAP_IMPACT_THRESHOLD,
            "Small swap should have minimal slippage"
        );
    }

    function testLargeSwapImpact() public {
        uint256 largeSwapAmount = INITIAL_LIQUIDITY_AMOUNT / 2; // 50% of pool liquidity
        uint256 bobToken0Before = token0.balanceOf(bob);
        uint256 bobToken1Before = token1.balanceOf(bob);

        // Get initial price using actual balances
        Edge storage edge = Store.edge(address(token0), address(token1));
        uint256 balance0 = token0.balanceOf(address(diamond));
        uint256 balance1 = token1.balanceOf(address(diamond));
        uint256 priceX128Before = edge.getPriceX128(
            uint128(balance0),
            uint128(balance1)
        );

        vm.startPrank(bob);
        swapFacet.swap(
            bob,
            address(token0),
            address(token1),
            int256(largeSwapAmount),
            0
        );
        vm.stopPrank();

        // Get final price using updated balances
        balance0 = token0.balanceOf(address(diamond));
        balance1 = token1.balanceOf(address(diamond));
        uint256 priceX128After = Store
            .edge(address(token0), address(token1))
            .getPriceX128(uint128(balance0), uint128(balance1));

        // Calculate price impact
        uint256 priceImpact = ((
            priceX128After > priceX128Before
                ? priceX128After - priceX128Before
                : priceX128Before - priceX128After
        ) * 1e18) / priceX128Before;

        assertGt(
            priceImpact,
            SMALL_SWAP_IMPACT_THRESHOLD,
            "Large swap should have significant price impact"
        );

        // Verify output amount shows significant slippage
        uint256 token1Received = token1.balanceOf(bob) - bobToken1Before;
        assertLt(
            token1Received,
            largeSwapAmount,
            "Large swap should have significant slippage"
        );
    }

    function testSequentialSwapsIncreasePriceImpact() public {
        uint256 swapAmount = INITIAL_LIQUIDITY_AMOUNT / 10; // 10% each swap

        // Get initial price using actual balances
        Edge storage edge = Store.edge(address(token0), address(token1));
        uint256 balance0 = token0.balanceOf(address(diamond));
        uint256 balance1 = token1.balanceOf(address(diamond));
        uint256 initialPriceX128 = edge.getPriceX128(
            uint128(balance0),
            uint128(balance1)
        );
        uint256 lastPriceX128 = initialPriceX128;

        // Perform multiple swaps
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(bob);
            swapFacet.swap(
                bob,
                address(token0),
                address(token1),
                int256(swapAmount),
                0
            );
            vm.stopPrank();

            // Get new price using updated balances
            balance0 = token0.balanceOf(address(diamond));
            balance1 = token1.balanceOf(address(diamond));
            uint256 newPriceX128 = Store
                .edge(address(token0), address(token1))
                .getPriceX128(uint128(balance0), uint128(balance1));

            // Calculate price impact for this swap
            uint256 swapImpact = ((
                newPriceX128 > lastPriceX128
                    ? newPriceX128 - lastPriceX128
                    : lastPriceX128 - newPriceX128
            ) * 1e18) / lastPriceX128;

            // Each subsequent swap should have larger price impact
            if (i > 0) {
                uint256 lastImpact = ((
                    lastPriceX128 > initialPriceX128
                        ? lastPriceX128 - initialPriceX128
                        : initialPriceX128 - lastPriceX128
                ) * 1e18) / initialPriceX128;
                assertGt(
                    swapImpact,
                    lastImpact,
                    "Sequential swaps should have increasing price impact"
                );
            }

            lastPriceX128 = newPriceX128;
        }
    }

    // Helper function to calculate price impact from prices in X128 format
    function calculatePriceImpact(
        uint256 priceX128Before,
        uint256 priceX128After
    ) internal pure returns (uint256) {
        return
            ((
                priceX128After > priceX128Before
                    ? priceX128After - priceX128Before
                    : priceX128Before - priceX128After
            ) * 1e18) / priceX128Before;
    }

    function testSwapRevertsForInsufficientLiquidity() public {
        // Remove all liquidity first
        vm.startPrank(alice);
        uint256 shares0 = liqFacet.addLiq(
            alice,
            closureId,
            address(token0),
            uint128(INITIAL_LIQUIDITY_AMOUNT)
        );
        uint256 shares1 = liqFacet.addLiq(
            alice,
            closureId,
            address(token1),
            uint128(INITIAL_LIQUIDITY_AMOUNT)
        );
        liqFacet.removeLiq(alice, closureId, shares0, "");
        liqFacet.removeLiq(alice, closureId, shares1, "");
        vm.stopPrank();

        // Try to swap
        vm.startPrank(bob);
        vm.expectRevert(); // Should revert due to insufficient liquidity
        swapFacet.swap(
            bob,
            address(token0),
            address(token1),
            int256(1000e18),
            0
        );
        vm.stopPrank();
    }

    function testSwapRevertsForZeroAmount() public {
        vm.startPrank(bob);
        vm.expectRevert(); // Should revert for zero amount
        swapFacet.swap(bob, address(token0), address(token1), 0, 0);
        vm.stopPrank();
    }

    function testSwapRevertsForInvalidTokenPair() public {
        MockERC20 invalidToken = new MockERC20("Invalid Token", "INVALID", 18);

        vm.startPrank(bob);
        vm.expectRevert(); // Should revert for invalid token pair
        swapFacet.swap(
            bob,
            address(invalidToken),
            address(token1),
            int256(1000e18),
            0
        );
        vm.stopPrank();
    }

    function testSwapRevertsForExtremePriceLimit() public {
        uint256 swapAmount = 1000e18;
        uint160 extremeLimit = type(uint160).max; // Unrealistic price limit

        vm.startPrank(bob);
        vm.expectRevert(); // Should revert for extreme price limit
        swapFacet.swap(
            bob,
            address(token0),
            address(token1),
            int256(swapAmount),
            extremeLimit
        );
        vm.stopPrank();
    }

    function testSwapWithMaximumPossibleAmount() public {
        uint256 maxAmount = type(uint128).max;

        // Mint maximum possible amount
        token0.mint(bob, maxAmount);

        vm.startPrank(bob);
        vm.expectRevert(); // Should revert due to insufficient liquidity for such large amount
        swapFacet.swap(
            bob,
            address(token0),
            address(token1),
            int256(maxAmount),
            0
        );
        vm.stopPrank();
    }

    function testSwapToSelf() public {
        uint256 swapAmount = 1000e18;

        vm.startPrank(bob);
        vm.expectRevert(); // Should revert when trying to swap a token for itself
        swapFacet.swap(
            bob,
            address(token0),
            address(token0),
            int256(swapAmount),
            0
        );
        vm.stopPrank();
    }

    function testSwapAndRemoveLiquidity() public {
        uint256 swapAmount = INITIAL_LIQUIDITY_AMOUNT / 10;
        uint256 removalAmount = INITIAL_LIQUIDITY_AMOUNT / 2;

        // First swap
        vm.startPrank(bob);
        swapFacet.swap(
            bob,
            address(token0),
            address(token1),
            int256(swapAmount),
            0
        );
        vm.stopPrank();

        // Then remove liquidity
        vm.startPrank(alice);
        uint256 shares0 = liqFacet.addLiq(
            alice,
            closureId,
            address(token0),
            uint128(removalAmount)
        );
        uint256 shares1 = liqFacet.addLiq(
            alice,
            closureId,
            address(token1),
            uint128(removalAmount)
        );

        uint256 token0Before = token0.balanceOf(alice);
        uint256 token1Before = token1.balanceOf(alice);

        liqFacet.removeLiq(alice, closureId, shares0, "");
        liqFacet.removeLiq(alice, closureId, shares1, "");

        // Verify tokens returned proportionally
        assertApproxEqRel(
            token0.balanceOf(alice) - token0Before,
            removalAmount,
            1e16,
            "Should receive proportional token0"
        );
        assertApproxEqRel(
            token1.balanceOf(alice) - token1Before,
            removalAmount,
            1e16,
            "Should receive proportional token1"
        );
        vm.stopPrank();
    }

    function testMultipleSwapsAndLiquidityChanges() public {
        uint256 swapAmount = INITIAL_LIQUIDITY_AMOUNT / 20;
        uint256 liquidityAmount = INITIAL_LIQUIDITY_AMOUNT / 10;

        for (uint i = 0; i < 5; i++) {
            // Swap token0 for token1
            vm.startPrank(bob);
            swapFacet.swap(
                bob,
                address(token0),
                address(token1),
                int256(swapAmount),
                0
            );
            vm.stopPrank();

            // Add liquidity
            vm.startPrank(alice);
            uint256 shares0 = liqFacet.addLiq(
                alice,
                closureId,
                address(token0),
                uint128(liquidityAmount)
            );
            uint256 shares1 = liqFacet.addLiq(
                alice,
                closureId,
                address(token1),
                uint128(liquidityAmount)
            );

            // Remove half of added liquidity
            liqFacet.removeLiq(alice, closureId, shares0 / 2, "");
            liqFacet.removeLiq(alice, closureId, shares1 / 2, "");
            vm.stopPrank();

            // Swap token1 for token0
            vm.startPrank(bob);
            swapFacet.swap(
                bob,
                address(token1),
                address(token0),
                int256(swapAmount),
                0
            );
            vm.stopPrank();
        }
    }

    function testConcurrentUsersOperations() public {
        address charlie = makeAddr("charlie");
        address dave = makeAddr("dave");

        // Fund additional users
        token0.mint(charlie, INITIAL_MINT_AMOUNT);
        token1.mint(charlie, INITIAL_MINT_AMOUNT);
        token0.mint(dave, INITIAL_MINT_AMOUNT);
        token1.mint(dave, INITIAL_MINT_AMOUNT);

        vm.startPrank(charlie);
        token0.approve(address(diamond), type(uint256).max);
        token1.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(dave);
        token0.approve(address(diamond), type(uint256).max);
        token1.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        // Multiple users perform operations
        uint256 amount = INITIAL_LIQUIDITY_AMOUNT / 10;

        // Charlie adds liquidity
        vm.startPrank(charlie);
        liqFacet.addLiq(charlie, closureId, address(token0), uint128(amount));
        liqFacet.addLiq(charlie, closureId, address(token1), uint128(amount));
        vm.stopPrank();

        // Bob swaps
        vm.startPrank(bob);
        swapFacet.swap(
            bob,
            address(token0),
            address(token1),
            int256(amount),
            0
        );
        vm.stopPrank();

        // Dave adds liquidity
        vm.startPrank(dave);
        liqFacet.addLiq(dave, closureId, address(token0), uint128(amount));
        liqFacet.addLiq(dave, closureId, address(token1), uint128(amount));
        vm.stopPrank();

        // Alice removes liquidity
        vm.startPrank(alice);
        uint256 shares0 = liqFacet.addLiq(
            alice,
            closureId,
            address(token0),
            uint128(amount)
        );
        uint256 shares1 = liqFacet.addLiq(
            alice,
            closureId,
            address(token1),
            uint128(amount)
        );
        liqFacet.removeLiq(alice, closureId, shares0, "");
        liqFacet.removeLiq(alice, closureId, shares1, "");
        vm.stopPrank();
    }
}
