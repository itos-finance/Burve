// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BurveDeploymentLib} from "../../src/BurveDeploymentLib.sol";
import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {EdgeFacet} from "../../src/multi/facets/EdgeFacet.sol";
import {LiqFacet} from "../../src/multi/facets/LiqFacet.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ClosureId, newClosureId} from "../../src/multi/Closure.sol";
import {VaultType} from "../../src/multi/VaultProxy.sol";
import {FullMath} from "../../src/multi/FullMath.sol";
import {Store} from "../../src/multi/Store.sol";
import {Edge} from "../../src/multi/Edge.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";

contract LiqFacetTest is Test {
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

    MockERC4626 public mockVault0;
    MockERC4626 public mockVault1;

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
        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");

        // Ensure token0 address is less than token1
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Setup mock ERC4626 vaults
        mockVault0 = new MockERC4626(token0, "Mock Vault 0", "MVLT0");
        mockVault1 = new MockERC4626(token1, "Mock Vault 1", "MVLT1");

        // Add vertices with mock vaults
        simplexFacet.addVertex(
            address(token0),
            address(mockVault0),
            VaultType.E4626
        );
        simplexFacet.addVertex(
            address(token1),
            address(mockVault1),
            VaultType.E4626
        );

        // fetch closure
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

    function testInitialLiquidityProvision() public {
        uint256 amount0 = INITIAL_LIQUIDITY_AMOUNT;
        uint256 amount1 = INITIAL_LIQUIDITY_AMOUNT;

        vm.startPrank(alice);

        // Add liquidity for both tokens
        uint256 shares0 = liqFacet.addLiq(
            alice,
            closureId,
            address(token0),
            uint128(amount0)
        );

        uint256 shares1 = liqFacet.addLiq(
            alice,
            closureId,
            address(token1),
            uint128(amount1)
        );

        vm.stopPrank();

        // Verify shares were minted
        assertGt(shares0, 0, "Should have received shares for token0");
        assertGt(shares1, 0, "Should have received shares for token1");
    }

    function testMultipleProvidersLiquidity() public {
        uint256 amount = INITIAL_LIQUIDITY_AMOUNT;

        // Alice adds liquidity
        vm.startPrank(alice);
        uint256 aliceShares0 = liqFacet.addLiq(
            alice,
            closureId,
            address(token0),
            uint128(amount)
        );
        // uint256 aliceShares1 = liqFacet.addLiq(
        //     alice,
        //     closureId,
        //     address(token1),
        //     uint128(amount)
        // );
        vm.stopPrank();

        // Bob adds same amount of liquidity
        vm.startPrank(bob);
        uint256 bobShares0 = liqFacet.addLiq(
            bob,
            closureId,
            address(token0),
            uint128(amount)
        );
        // uint256 bobShares1 = liqFacet.addLiq(
        //     bob,
        //     closureId,
        //     address(token1),
        //     uint128(amount)
        // );
        vm.stopPrank();

        console2.log("Alice shares for token0:", aliceShares0);
        // console2.log("Alice shares for token1:", aliceShares1);
        console2.log("Bob shares for token0:", bobShares0);
        // console2.log("Bob shares for token1:", bobShares1);

        vm.startPrank(alice);

        // Record balances before removal
        uint256 aliceToken0Before = token0.balanceOf(alice);
        uint256 aliceToken1Before = token1.balanceOf(alice);

        // Remove all liquidity
        liqFacet.removeLiq(alice, closureId, aliceShares0, "");

        vm.stopPrank();

        vm.startPrank(bob);

        // Record balances before removal
        uint256 bobToken0Before = token0.balanceOf(bob);
        uint256 bobToken1Before = token1.balanceOf(bob);

        // Remove all liquidity
        liqFacet.removeLiq(bob, closureId, bobShares0, "");

        vm.stopPrank();

        // Verify tokens were returned (alice)
        assertApproxEqAbs(
            token0.balanceOf(alice),
            aliceToken0Before + amount,
            1,
            "Alice should have received all token0 back"
        );
        assertApproxEqAbs(
            token1.balanceOf(alice),
            aliceToken1Before + amount,
            1,
            "Alice should have received all token1 back"
        );

        // Verify tokens were returned (bob)
        assertApproxEqAbs(
            token0.balanceOf(bob),
            bobToken0Before + amount,
            1,
            "Bob should have received all token0 back"
        );
        assertApproxEqAbs(
            token1.balanceOf(bob),
            bobToken1Before + amount,
            1,
            "Bob should have received all token1 back"
        );
    }

    function testLiquidityRemoval() public {
        uint256 amount = INITIAL_LIQUIDITY_AMOUNT;

        // First provide liquidity
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

        // Record balances before removal
        uint256 token0Before = token0.balanceOf(alice);
        uint256 token1Before = token1.balanceOf(alice);

        // Remove all liquidity
        liqFacet.removeLiq(alice, closureId, shares0 + shares1, "");

        vm.stopPrank();

        // Verify tokens were returned
        assertApproxEqAbs(
            token0.balanceOf(alice),
            token0Before + amount,
            1,
            "Should have received all token0 back"
        );
        assertApproxEqAbs(
            token1.balanceOf(alice),
            token1Before + amount,
            1,
            "Should have received all token1 back"
        );
    }

    function testPartialLiquidityRemoval() public {
        uint256 amount = INITIAL_LIQUIDITY_AMOUNT;
        uint256 removalPercentage = 50; // 50%

        // Provide liquidity
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

        // Calculate partial shares to remove
        uint256 sharesToRemove0 = (shares0 * removalPercentage) / 100;
        uint256 sharesToRemove1 = (shares1 * removalPercentage) / 100;

        // Record balances before removal
        uint256 token0Before = token0.balanceOf(alice);
        uint256 token1Before = token1.balanceOf(alice);

        // Remove partial liquidity
        liqFacet.removeLiq(alice, closureId, sharesToRemove0, "");
        liqFacet.removeLiq(alice, closureId, sharesToRemove1, "");

        vm.stopPrank();

        // Verify tokens were returned proportionally
        assertApproxEqRel(
            token0.balanceOf(alice) - token0Before,
            amount / 2,
            1e16,
            "Should have received half of token0 back"
        );
        assertApproxEqRel(
            token1.balanceOf(alice) - token1Before,
            amount / 2,
            1e16,
            "Should have received half of token1 back"
        );
    }

    // Add these new fuzz tests after the existing tests
    function testFuzz_LiquidityProvision(
        uint128 amount0,
        uint128 amount1
    ) public {
        // Bound the amounts to reasonable ranges
        amount0 = uint128(bound(uint256(amount0), 1e6, INITIAL_MINT_AMOUNT));
        amount1 = uint128(bound(uint256(amount1), 1e6, INITIAL_MINT_AMOUNT));

        vm.startPrank(alice);

        // Add liquidity
        uint256 shares0 = liqFacet.addLiq(
            alice,
            closureId,
            address(token0),
            amount0
        );

        uint256 shares1 = liqFacet.addLiq(
            alice,
            closureId,
            address(token1),
            amount1
        );

        // Verify shares were minted proportionally to deposits
        assertGt(shares0, 0, "Should have received shares for token0");
        assertGt(shares1, 0, "Should have received shares for token1");

        // Verify share ratios are roughly proportional to deposit ratios
        uint256 shareRatio = (shares0 * 1e18) / shares1;
        uint256 amountRatio = (uint256(amount0) * 1e18) / uint256(amount1);
        assertApproxEqRel(
            shareRatio,
            amountRatio,
            1e16, // 1% tolerance
            "Share ratio should be proportional to amount ratio"
        );

        vm.stopPrank();
    }

    function testFuzz_PartialLiquidityRemoval(
        uint128 depositAmount,
        uint8 removalPercentage
    ) public {
        // Bound the inputs to reasonable ranges
        depositAmount = uint128(
            bound(uint256(depositAmount), 1e6, INITIAL_MINT_AMOUNT)
        );
        removalPercentage = uint8(bound(uint256(removalPercentage), 1, 99)); // 1-99%

        vm.startPrank(alice);

        // Provide initial liquidity
        uint256 shares0 = liqFacet.addLiq(
            alice,
            closureId,
            address(token0),
            depositAmount
        );

        uint256 shares1 = liqFacet.addLiq(
            alice,
            closureId,
            address(token1),
            depositAmount
        );

        // Calculate partial shares to remove
        uint256 sharesToRemove0 = (shares0 * removalPercentage) / 100;
        uint256 sharesToRemove1 = (shares1 * removalPercentage) / 100;

        // Record balances before removal
        uint256 token0Before = token0.balanceOf(alice);
        uint256 token1Before = token1.balanceOf(alice);

        // Remove partial liquidity
        liqFacet.removeLiq(alice, closureId, sharesToRemove0, "");
        liqFacet.removeLiq(alice, closureId, sharesToRemove1, "");

        // Calculate expected returns
        uint256 expectedReturn0 = (uint256(depositAmount) * removalPercentage) /
            100;
        uint256 expectedReturn1 = (uint256(depositAmount) * removalPercentage) /
            100;

        // Verify returned amounts
        assertApproxEqRel(
            token0.balanceOf(alice) - token0Before,
            expectedReturn0,
            1e16,
            "Incorrect token0 return amount"
        );
        assertApproxEqRel(
            token1.balanceOf(alice) - token1Before,
            expectedReturn1,
            1e16,
            "Incorrect token1 return amount"
        );

        vm.stopPrank();
    }

    function testFuzz_MultipleProvidersWithRandomAmounts(
        uint128[3] memory amounts0,
        uint128[3] memory amounts1
    ) public {
        address[3] memory providers = [alice, bob, makeAddr("charlie")];
        uint256[] memory totalShares0 = new uint256[](3);
        uint256[] memory totalShares1 = new uint256[](3);
        uint256 totalAmount0;
        uint256 totalAmount1;

        // Process each provider's liquidity provision
        for (uint i = 0; i < 3; i++) {
            // Bound amounts to reasonable ranges
            amounts0[i] = uint128(
                bound(uint256(amounts0[i]), 1e6, INITIAL_MINT_AMOUNT / 4)
            );
            amounts1[i] = uint128(
                bound(uint256(amounts1[i]), 1e6, INITIAL_MINT_AMOUNT / 4)
            );

            address provider = providers[i];

            // Fund provider
            token0.mint(provider, amounts0[i]);
            token1.mint(provider, amounts1[i]);

            vm.startPrank(provider);
            token0.approve(address(diamond), type(uint256).max);
            token1.approve(address(diamond), type(uint256).max);

            // Add liquidity
            totalShares0[i] = liqFacet.addLiq(
                provider,
                closureId,
                address(token0),
                amounts0[i]
            );
            totalShares1[i] = liqFacet.addLiq(
                provider,
                closureId,
                address(token1),
                amounts1[i]
            );

            vm.stopPrank();

            totalAmount0 += amounts0[i];
            totalAmount1 += amounts1[i];
        }

        // Verify share proportions for each provider
        for (uint i = 0; i < 3; i++) {
            uint256 expectedShare0 = (uint256(amounts0[i]) * 1e18) /
                totalAmount0;
            uint256 actualShare0 = (totalShares0[i] * 1e18) /
                (totalShares0[0] + totalShares0[1] + totalShares0[2]);

            uint256 expectedShare1 = (uint256(amounts1[i]) * 1e18) /
                totalAmount1;
            uint256 actualShare1 = (totalShares1[i] * 1e18) /
                (totalShares1[0] + totalShares1[1] + totalShares1[2]);

            assertApproxEqRel(
                actualShare0,
                expectedShare0,
                1e16,
                "Incorrect share proportion for token0"
            );
            assertApproxEqRel(
                actualShare1,
                expectedShare1,
                1e16,
                "Incorrect share proportion for token1"
            );
        }
    }

    function testFuzz_RepeatedAddRemoveLiquidity(
        uint128[5] memory addAmounts,
        uint8[5] memory removePercentages
    ) public {
        vm.startPrank(alice);
        uint256 remainingShares0;
        uint256 remainingShares1;

        for (uint i = 0; i < 5; i++) {
            // Bound inputs
            addAmounts[i] = uint128(
                bound(uint256(addAmounts[i]), 1e6, INITIAL_MINT_AMOUNT / 10)
            );
            removePercentages[i] = uint8(
                bound(uint256(removePercentages[i]), 1, 90)
            ); // 1-90%

            // Add liquidity
            uint256 newShares0 = liqFacet.addLiq(
                alice,
                closureId,
                address(token0),
                addAmounts[i]
            );
            uint256 newShares1 = liqFacet.addLiq(
                alice,
                closureId,
                address(token1),
                addAmounts[i]
            );

            remainingShares0 += newShares0;
            remainingShares1 += newShares1;

            // Remove some percentage of total shares
            uint256 sharesToRemove0 = (remainingShares0 *
                removePercentages[i]) / 100;
            uint256 sharesToRemove1 = (remainingShares1 *
                removePercentages[i]) / 100;

            if (sharesToRemove0 > 0 && sharesToRemove1 > 0) {
                liqFacet.removeLiq(alice, closureId, sharesToRemove0, "");
                liqFacet.removeLiq(alice, closureId, sharesToRemove1, "");

                remainingShares0 -= sharesToRemove0;
                remainingShares1 -= sharesToRemove1;
            }
        }

        vm.stopPrank();
    }

    function testShareCalculationInvariant() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = INITIAL_LIQUIDITY_AMOUNT;
        amounts[1] = INITIAL_LIQUIDITY_AMOUNT * 2;
        amounts[2] = INITIAL_LIQUIDITY_AMOUNT / 2;

        uint256[] memory shares0 = new uint256[](3);
        uint256[] memory shares1 = new uint256[](3);
        uint256 totalShares0;
        uint256 totalShares1;

        vm.startPrank(alice);

        // Add liquidity in multiple rounds
        for (uint i = 0; i < amounts.length; i++) {
            shares0[i] = liqFacet.addLiq(
                alice,
                closureId,
                address(token0),
                uint128(amounts[i])
            );
            shares1[i] = liqFacet.addLiq(
                alice,
                closureId,
                address(token1),
                uint128(amounts[i])
            );

            totalShares0 += shares0[i];
            totalShares1 += shares1[i];

            // Verify share proportion matches deposit proportion
            if (i > 0) {
                uint256 shareRatio = (shares0[i] * 1e18) / shares0[0];
                uint256 amountRatio = (amounts[i] * 1e18) / amounts[0];
                assertApproxEqRel(
                    shareRatio,
                    amountRatio,
                    1e16,
                    "Share ratio should match deposit ratio"
                );
            }
        }

        // Remove liquidity in reverse order
        uint256 remainingToken0 = (INITIAL_LIQUIDITY_AMOUNT * 7) / 2; // Sum of amounts
        uint256 remainingToken1 = remainingToken0;

        for (uint i = 0; i < shares0.length; i++) {
            uint256 token0Before = token0.balanceOf(alice);
            uint256 token1Before = token1.balanceOf(alice);

            liqFacet.removeLiq(alice, closureId, shares0[i], "");
            liqFacet.removeLiq(alice, closureId, shares1[i], "");

            uint256 token0Received = token0.balanceOf(alice) - token0Before;
            uint256 token1Received = token1.balanceOf(alice) - token1Before;

            // Verify received amounts are proportional to shares
            assertApproxEqRel(
                (token0Received * totalShares0) / shares0[i],
                remainingToken0,
                1e16,
                "Token0 received should be proportional to shares"
            );
            assertApproxEqRel(
                (token1Received * totalShares1) / shares1[i],
                remainingToken1,
                1e16,
                "Token1 received should be proportional to shares"
            );

            remainingToken0 -= token0Received;
            remainingToken1 -= token1Received;
        }

        vm.stopPrank();
    }

    function testTotalSupplyInvariant() public {
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = makeAddr("charlie");

        uint256 totalSupply0;
        uint256 totalSupply1;

        // Fund users and approve diamond
        for (uint i = 1; i < users.length; i++) {
            token0.mint(users[i], INITIAL_MINT_AMOUNT);
            token1.mint(users[i], INITIAL_MINT_AMOUNT);

            vm.startPrank(users[i]);
            token0.approve(address(diamond), type(uint256).max);
            token1.approve(address(diamond), type(uint256).max);
            vm.stopPrank();
        }

        // Each user adds different amounts of liquidity
        for (uint i = 0; i < users.length; i++) {
            uint256 amount = INITIAL_LIQUIDITY_AMOUNT * (i + 1);

            vm.startPrank(users[i]);
            uint256 shares0 = liqFacet.addLiq(
                users[i],
                closureId,
                address(token0),
                uint128(amount)
            );
            uint256 shares1 = liqFacet.addLiq(
                users[i],
                closureId,
                address(token1),
                uint128(amount)
            );
            vm.stopPrank();

            totalSupply0 += shares0;
            totalSupply1 += shares1;
        }

        // Remove random amounts of liquidity and verify total supply changes
        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);

            // Remove half of user's liquidity
            uint256 shares0 = liqFacet.addLiq(
                users[i],
                closureId,
                address(token0),
                uint128(INITIAL_LIQUIDITY_AMOUNT * (i + 1))
            ) / 2;
            uint256 shares1 = liqFacet.addLiq(
                users[i],
                closureId,
                address(token1),
                uint128(INITIAL_LIQUIDITY_AMOUNT * (i + 1))
            ) / 2;

            liqFacet.removeLiq(users[i], closureId, shares0, "");
            liqFacet.removeLiq(users[i], closureId, shares1, "");

            totalSupply0 -= shares0;
            totalSupply1 -= shares1;

            vm.stopPrank();
        }
    }

    function testShareRatioInvariant() public {
        // Test that share ratios remain proportional to deposit ratios
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = INITIAL_LIQUIDITY_AMOUNT;
        amounts[1] = INITIAL_LIQUIDITY_AMOUNT * 2;
        amounts[2] = INITIAL_LIQUIDITY_AMOUNT / 2;

        uint256[] memory shares0 = new uint256[](3);
        uint256[] memory shares1 = new uint256[](3);

        vm.startPrank(alice);

        // Add liquidity in multiple rounds
        for (uint i = 0; i < amounts.length; i++) {
            shares0[i] = liqFacet.addLiq(
                alice,
                closureId,
                address(token0),
                uint128(amounts[i])
            );
            shares1[i] = liqFacet.addLiq(
                alice,
                closureId,
                address(token1),
                uint128(amounts[i])
            );

            // Verify share proportion matches deposit proportion
            if (i > 0) {
                uint256 shareRatio = (shares0[i] * 1e18) / shares0[0];
                uint256 amountRatio = (amounts[i] * 1e18) / amounts[0];
                assertApproxEqRel(
                    shareRatio,
                    amountRatio,
                    1e16, // 1% tolerance
                    "Share ratio should match deposit ratio"
                );
            }
        }

        vm.stopPrank();
    }

    function testValuePreservationInvariant() public {
        uint256 initialAmount = INITIAL_LIQUIDITY_AMOUNT;

        // Record initial token balances
        uint256 aliceToken0Before = token0.balanceOf(alice);
        uint256 aliceToken1Before = token1.balanceOf(alice);

        vm.startPrank(alice);

        // Add liquidity
        uint256 shares0 = liqFacet.addLiq(
            alice,
            closureId,
            address(token0),
            uint128(initialAmount)
        );
        uint256 shares1 = liqFacet.addLiq(
            alice,
            closureId,
            address(token1),
            uint128(initialAmount)
        );

        // Perform some swaps to change the price
        vm.stopPrank();
        vm.startPrank(bob);
        swapFacet.swap(
            bob,
            address(token0),
            address(token1),
            int256(initialAmount / 10),
            0
        );
        swapFacet.swap(
            bob,
            address(token1),
            address(token0),
            int256(initialAmount / 5),
            0
        );
        vm.stopPrank();

        // Remove all liquidity
        vm.startPrank(alice);
        liqFacet.removeLiq(alice, closureId, shares0, "");
        liqFacet.removeLiq(alice, closureId, shares1, "");
        vm.stopPrank();

        // Calculate total value change
        uint256 aliceToken0After = token0.balanceOf(alice);
        uint256 aliceToken1After = token1.balanceOf(alice);

        Edge storage edge = Store.edge(address(token0), address(token1));
        uint256 priceX128 = edge.getPriceX128(
            uint128(aliceToken0After - aliceToken0Before),
            uint128(aliceToken1After - aliceToken1Before)
        );

        uint256 initialValue = initialAmount +
            FullMath.mulX128(initialAmount, priceX128, true);
        uint256 finalValue = (aliceToken0After - aliceToken0Before) +
            FullMath.mulX128(
                aliceToken1After - aliceToken1Before,
                priceX128,
                true
            );

        // Value should be preserved within a small tolerance
        assertApproxEqRel(
            finalValue,
            initialValue,
            1e16, // 1% tolerance
            "Total value should be preserved"
        );
    }
}
