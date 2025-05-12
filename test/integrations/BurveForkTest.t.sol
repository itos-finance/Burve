// SPDX-License-Identifier: BUSL-1.1
// Copyright 2024 Itos Inc.
pragma solidity ^0.8.27;

import {console2 as console} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ForkableTest} from "Commons/Test/ForkableTest.sol";
import {Auto165} from "Commons/ERC/Auto165.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {DiamondCutFacet} from "Commons/Diamond/facets/DiamondCutFacet.sol";

import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {VaultFacet} from "../../src/multi/facets/VaultFacet.sol";
import {VaultType} from "../../src/multi/vertex/VaultProxy.sol";
import {InitLib, BurveFacets} from "../../src/multi/InitLib.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";

/// @title BurveForkTest - base contract for fork testing on Burve
/// @notice sets up the e2e contracts for fork testing of Burve
/// includes diamond creation, facet setup, and token/vault setup
contract BurveForkTest is ForkableTest, Auto165 {
    uint256 constant INITIAL_MINT_AMOUNT = 1000000e18;
    uint256 constant INITIAL_LIQUIDITY_AMOUNT = 5e18;
    uint256 constant INITIAL_DEPOSIT_AMOUNT = 5e18;

    // Core contracts
    SimplexDiamond public diamond;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;
    ValueFacet public valueFacet;
    VaultFacet public vaultFacet;

    // USD Tokens
    IERC20 public usda;
    IERC20 public nect;
    IERC20 public usdc;
    IERC20 public usdt;

    // ERC4626 Vaults
    IERC4626 public usdaVault;
    IERC4626 public nectVault;
    IERC4626 public usdcVault;
    IERC4626 public usdtVault;

    // Vault addresses
    address constant USDA_VAULT = 0x0d1A3CE611CE10b72d4A14DaE2A4443855B6DFc3;
    address constant NECT_VAULT = 0x474F32Eb1754827C531C16330Db07531e901BcBe;
    address constant USDC_VAULT = 0x444868B6e8079ac2c55eea115250f92C2b2c4D14;
    address constant USDT_VAULT = 0xF2d2d55Daf93b0660297eaA10969eBe90ead5CE8;

    uint16 closureId = 15; // all 4 tokens
    // Fund the deployer with tokens - using a larger amount for liquidity
    uint256 usdaAmount = 100 * 1e18; // 100 USDA (18 decimals)
    uint256 nectAmount = 100 * 1e18; // 100 NECT (18 decimals)
    uint256 usdcAmount = 100 * 1e6; // 100 USDC (6 decimals)
    uint256 usdtAmount = 100 * 1e6; // 100 USDT (6 decimals)

    function _newDiamond() internal {
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        vm.startPrank(deployer);

        BurveFacets memory bFacets = InitLib.deployFacets();
        diamond = new SimplexDiamond(bFacets, "ValueToken", "BVT");

        simplexFacet = SimplexFacet(address(diamond));
        swapFacet = SwapFacet(address(diamond));
        valueFacet = ValueFacet(address(diamond));
        vaultFacet = VaultFacet(address(diamond));

        vm.stopPrank();
    }

    function forkSetup() internal virtual override {
        string memory forkUrl = vm.envString("FORK_URL");
        vm.createFork(forkUrl);
        vm.selectFork(vm.createFork(forkUrl));

        // Initialize vault interfaces
        usdaVault = IERC4626(USDA_VAULT);
        nectVault = IERC4626(NECT_VAULT);
        usdcVault = IERC4626(USDC_VAULT);
        usdtVault = IERC4626(USDT_VAULT);

        // Get underlying tokens from vaults
        usda = IERC20(usdaVault.asset());
        nect = IERC20(nectVault.asset());
        usdc = IERC20(usdcVault.asset());
        usdt = IERC20(usdtVault.asset());

        _newDiamond();
    }

    function deploySetup() internal pure override {}

    function postSetup() internal override {
        // Label addresses for better trace output
        vm.label(address(usda), "USDA");
        vm.label(address(nect), "NECT");
        vm.label(address(usdc), "USDC");
        vm.label(address(usdt), "USDT");
        vm.label(address(usdaVault), "vUSDA");
        vm.label(address(nectVault), "vNECT");
        vm.label(address(usdcVault), "vUSDC");
        vm.label(address(usdtVault), "vUSDT");
        vm.label(address(diamond), "BurveDiamond");

        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        vm.startPrank(deployer);

        // Add vertices for each token with their corresponding vaults
        simplexFacet.addVertex(
            address(usda),
            address(usdaVault),
            VaultType.E4626
        );
        simplexFacet.addVertex(
            address(nect),
            address(nectVault),
            VaultType.E4626
        );
        simplexFacet.addVertex(
            address(usdc),
            address(usdcVault),
            VaultType.E4626
        );
        simplexFacet.addVertex(
            address(usdt),
            address(usdtVault),
            VaultType.E4626
        );

        _dealTokens(deployer);
        _addClosure();

        vm.stopPrank();
    }

    function _dealTokens(address recipient) internal {
        deal(address(usda), recipient, usdaAmount);
        deal(address(nect), recipient, nectAmount);
        deal(address(usdc), recipient, usdcAmount);
        deal(address(usdt), recipient, usdtAmount);

        // Approve tokens for diamond
        vm.startPrank(recipient);
        usda.approve(address(diamond), type(uint256).max);
        nect.approve(address(diamond), type(uint256).max);
        usdc.approve(address(diamond), type(uint256).max);
        usdt.approve(address(diamond), type(uint256).max);
        vm.stopPrank();
    }

    function _deposit(
        address deployer
    ) internal returns (uint256[] memory valueAdded) {
        _dealTokens(deployer);

        // Print initial balances
        console.log("Initial USDA balance:", usda.balanceOf(deployer));
        console.log("Initial NECT balance:", nect.balanceOf(deployer));
        console.log("Initial USDC balance:", usdc.balanceOf(deployer));
        console.log("Initial USDT balance:", usdt.balanceOf(deployer));

        // Approve tokens for diamond
        usda.approve(address(diamond), type(uint256).max);
        nect.approve(address(diamond), type(uint256).max);
        usdc.approve(address(diamond), type(uint256).max);
        usdt.approve(address(diamond), type(uint256).max);

        vm.startPrank(deployer);

        valueAdded = new uint256[](4);
        // Add initial liquidity for each token
        valueAdded[0] = valueFacet.addSingleForValue(
            deployer,
            closureId,
            address(usda),
            uint128(usdaAmount),
            0, // no BGT value
            0 // no min value
        );

        valueAdded[1] = valueFacet.addSingleForValue(
            deployer,
            closureId,
            address(nect),
            uint128(nectAmount),
            0, // no BGT value
            0 // no min value
        );

        valueAdded[2] = valueFacet.addSingleForValue(
            deployer,
            closureId,
            address(usdc),
            uint128(usdcAmount),
            0, // no BGT value
            0 // no min value
        );

        valueAdded[3] = valueFacet.addSingleForValue(
            deployer,
            closureId,
            address(usdt),
            uint128(usdtAmount),
            0, // no BGT value
            0 // no min value
        );

        vm.stopPrank();
    }

    function _addClosure() internal {
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        vm.startPrank(deployer);

        uint128 startingTarget = 100e18; // 100 units in 18 decimals
        uint128 baseFeeX128 = 1 << 127; // 50%
        uint128 protocolTakeX128 = 1 << 127; // 50% of fees to protocol

        // Add closure with initial liquidity
        simplexFacet.addClosure(
            closureId,
            startingTarget,
            baseFeeX128,
            protocolTakeX128
        );

        vm.stopPrank();
    }

    function testAddLiquidityUSDPool() public {
        address user = makeAddr("user");
        vm.startPrank(user);

        _deposit(user);

        // Print final balances
        console.log("Final USDA balance:", usda.balanceOf(user));
        console.log("Final NECT balance:", nect.balanceOf(user));
        console.log("Final USDC balance:", usdc.balanceOf(user));
        console.log("Final USDT balance:", usdt.balanceOf(user));

        // Print pool balances
        console.log("Pool USDA balance:", usda.balanceOf(address(diamond)));
        console.log("Pool NECT balance:", nect.balanceOf(address(diamond)));
        console.log("Pool USDC balance:", usdc.balanceOf(address(diamond)));
        console.log("Pool USDT balance:", usdt.balanceOf(address(diamond)));

        // Verify closure was created and has liquidity
        (
            uint8 n,
            ,
            ,
            uint256 valueStaked,
            uint256 bgtValueStaked
        ) = simplexFacet.getClosureValue(closureId);

        assertEq(n, 4, "Should have 4 tokens in closure");
        assertGt(valueStaked, 0, "Should have value staked");
        assertEq(bgtValueStaked, 0, "Should not have BGT value staked");

        // Verify each token has liquidity
        assertGt(
            usda.balanceOf(address(diamond)),
            0,
            "Should have USDA liquidity"
        );
        assertGt(
            nect.balanceOf(address(diamond)),
            0,
            "Should have NECT liquidity"
        );
        assertGt(
            usdc.balanceOf(address(diamond)),
            0,
            "Should have USDC liquidity"
        );
        assertGt(
            usdt.balanceOf(address(diamond)),
            0,
            "Should have USDT liquidity"
        );

        vm.stopPrank();
    }

    function testSwapUSDPair() public forkOnly {
        // Start acting as a new user for depositing
        address depositor = makeAddr("depositor");
        _deposit(depositor);

        // Start acting as a new user for swapping
        address user = makeAddr("user");
        vm.startPrank(user);

        // Fund the user with USDA for swapping
        uint256 swapAmount = 1e18; // Swap 1 USDA
        deal(address(usda), user, swapAmount);

        // Approve USDA for the diamond
        usda.approve(address(diamond), type(uint256).max);

        // Print initial balances
        console.log("Initial USDA balance:", usda.balanceOf(user));
        console.log("Initial NECT balance:", nect.balanceOf(user));
        console.log(
            "Initial Pool USDA balance:",
            usda.balanceOf(address(diamond))
        );
        console.log(
            "Initial Pool NECT balance:",
            nect.balanceOf(address(diamond))
        );

        // Get quote for swap
        (, uint256 expectedNectAmount, uint256 valueExchangedX128) = swapFacet
            .simSwap(
                address(usda), // token in
                address(nect), // token out
                int256(swapAmount), // amount in
                closureId // closure id
            );

        console.log("Expected NECT output:", expectedNectAmount);
        console.log("Value exchanged:", valueExchangedX128);

        require(
            nect.balanceOf(address(diamond)) >= expectedNectAmount,
            "Insufficient NECT in pool"
        );

        // Store initial balances
        uint256 initialUsdaBalance = usda.balanceOf(user);
        uint256 initialUsdaVaultBalance = usdaVault.totalAssets();
        uint256 initialNectVaultBalance = nectVault.totalAssets();

        // Perform the swap
        (uint256 usdaIn, uint256 nectOut) = swapFacet.swap(
            user, // recipient
            address(usda), // token in
            address(nect), // token out
            int256(swapAmount), // amount in
            0, // amount limit (no limit)
            closureId // closure id
        );

        // Print final balances
        console.log("Final USDA balance:", usda.balanceOf(user));
        console.log(
            "Final Pool USDA balance:",
            usda.balanceOf(address(diamond))
        );
        console.log("Final NECT balance:", nect.balanceOf(user));
        console.log(
            "Final Pool NECT balance:",
            nect.balanceOf(address(diamond))
        );
        console.log("USDA in:", usdaIn);
        console.log("NECT out:", nectOut);

        // Print vault balance changes
        console.log("Initial USDA Vault balance:", initialUsdaVaultBalance);
        console.log("Final USDA Vault balance:", usdaVault.totalAssets());
        console.log("Initial NECT Vault balance:", initialNectVaultBalance);
        console.log("Final NECT Vault balance:", nectVault.totalAssets());

        // Verify the swap was successful
        assertGt(nectOut, 0, "Should have received NECT");
        assertEq(
            usda.balanceOf(user),
            initialUsdaBalance - usdaIn,
            "Should have spent USDA amount"
        );
        assertApproxEqRel(
            nectOut,
            expectedNectAmount,
            0.001e18, // 0.1% tolerance
            "Received amount should be close to simulated amount"
        );

        // Verify vault balances changed
        assertNotEq(
            usdaVault.totalAssets(),
            initialUsdaVaultBalance,
            "USDA vault balance should change"
        );
        assertNotEq(
            nectVault.totalAssets(),
            initialNectVaultBalance,
            "NECT vault balance should change"
        );

        vm.stopPrank();
    }

    function testRemoveValueUSDPool() public {
        address user = makeAddr("user");

        _deposit(user);

        (
            uint256 value,
            uint256 bgtValue, // earnings
            ,

        ) = // bgtEarnings
            valueFacet.queryValue(user, closureId);

        // Print initial balances
        console.log("Initial value:", value);
        console.log("Initial BGT value:", bgtValue);

        // Store initial vault balances
        uint256 initialUsdaVaultBalance = usdaVault.totalAssets();
        uint256 initialNectVaultBalance = nectVault.totalAssets();
        uint256 initialUsdcVaultBalance = usdcVault.totalAssets();
        uint256 initialUsdtVaultBalance = usdtVault.totalAssets();

        vm.startPrank(user);

        // Remove value for each token using their actual value contribution
        uint256[MAX_TOKENS] memory receivedBalances = valueFacet.removeValue(
            user,
            closureId,
            uint128(value),
            uint128(bgtValue)
        );

        // Print vault balance changes
        console.log("Initial USDA Vault balance:", initialUsdaVaultBalance);
        console.log("Final USDA Vault balance:", usdaVault.totalAssets());
        console.log("Initial NECT Vault balance:", initialNectVaultBalance);
        console.log("Final NECT Vault balance:", nectVault.totalAssets());
        console.log("Initial USDC Vault balance:", initialUsdcVaultBalance);
        console.log("Final USDC Vault balance:", usdcVault.totalAssets());
        console.log("Initial USDT Vault balance:", initialUsdtVaultBalance);
        console.log("Final USDT Vault balance:", usdtVault.totalAssets());

        // Verify vault balances are reduced by exact amounts (allowing 1 token difference)
        assertApproxEqAbs(
            usdaVault.totalAssets(),
            initialUsdaVaultBalance - receivedBalances[0],
            1, // 1 USDA (18 decimals)
            "USDA vault balance should be reduced by approximate amount"
        );
        assertApproxEqAbs(
            nectVault.totalAssets(),
            initialNectVaultBalance - receivedBalances[1],
            1, // 1 NECT (18 decimals)
            "NECT vault balance should be reduced by approximate amount"
        );
        assertApproxEqAbs(
            usdcVault.totalAssets(),
            initialUsdcVaultBalance - receivedBalances[2],
            1, // 1 USDC (6 decimals)
            "USDC vault balance should be reduced by approximate amount"
        );
        assertApproxEqAbs(
            usdtVault.totalAssets(),
            initialUsdtVaultBalance - receivedBalances[3],
            1, // 1 USDT (6 decimals)
            "USDT vault balance should be reduced by approximate amount"
        );

        vm.stopPrank();
    }
}
