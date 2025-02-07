// SPDX-License-Identifier: BUSL-1.1
// Copyright 2024 Itos Inc.
pragma solidity ^0.8.27;

import {console2 as console} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ForkableTest} from "Commons/Test/ForkableTest.sol";
import {Auto165} from "Commons/ERC/Auto165.sol";

import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {EdgeFacet} from "../../src/multi/facets/EdgeFacet.sol";
import {LiqFacet} from "../../src/multi/facets/LiqFacet.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {ViewFacet} from "../../src/multi/facets/ViewFacet.sol";
import {BurveFacets, InitLib} from "../../src/InitLib.sol";
import {BurveMultiLPToken} from "../../src/multi/LPToken.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {VaultType} from "../../src/multi/VaultProxy.sol";

/// @title BurveForkTest - base contract for fork testing on Burve
/// @notice sets up the e2e contracts for fork testing of Burve
/// includes diamond creation, facet setup, and token/vault setup
contract BurveForkTest is ForkableTest, Auto165 {
    // Core contracts
    SimplexDiamond public diamond;
    LiqFacet public liqFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;
    ViewFacet public viewFacet;

    // Real tokens
    IERC20 public honey;
    IERC20 public dai;
    IERC20 public mim;
    IERC20 public mead;

    // Mock vaults
    MockERC4626 public mockHoneyVault;
    MockERC4626 public mockDaiVault;
    MockERC4626 public mockMimVault;
    MockERC4626 public mockMeadVault;

    // Constants
    uint256 public constant INITIAL_MINT_AMOUNT = 1000000e18;
    uint256 public constant INITIAL_LIQUIDITY_AMOUNT = 5e18;
    uint256 public constant INITIAL_DEPOSIT_AMOUNT = 5e18;

    function forkSetup() internal virtual override {
        // Initialize token interfaces from real addresses
        honey = IERC20(vm.envAddress("HONEY_ADDRESS"));
        dai = IERC20(vm.envAddress("DAI_ADDRESS"));
        mim = IERC20(vm.envAddress("MIM_ADDRESS"));
        mead = IERC20(vm.envAddress("MEAD_ADDRESS"));

        // Initialize existing vault interfaces
        mockHoneyVault = MockERC4626(vm.envAddress("HONEY_VAULT_ADDRESS"));
        mockDaiVault = MockERC4626(vm.envAddress("DAI_VAULT_ADDRESS"));
        mockMimVault = MockERC4626(vm.envAddress("MIM_VAULT_ADDRESS"));
        mockMeadVault = MockERC4626(vm.envAddress("MEAD_VAULT_ADDRESS"));

        // Initialize existing diamond and facets
        diamond = SimplexDiamond(payable(vm.envAddress("DIAMOND_ADDRESS")));
        liqFacet = LiqFacet(address(diamond));
        simplexFacet = SimplexFacet(address(diamond));
        swapFacet = SwapFacet(address(diamond));
        viewFacet = ViewFacet(address(diamond));
    }

    function deploySetup() internal pure override {
        revert("Use fork testing for Burve integration tests");
    }

    function postSetup() internal override {
        // Label addresses for better trace output
        vm.label(address(honey), "HONEY");
        vm.label(address(dai), "DAI");
        vm.label(address(mim), "MIM");
        vm.label(address(mead), "MEAD");
        vm.label(address(mockHoneyVault), "vHONEY");
        vm.label(address(mockDaiVault), "vDAI");
        vm.label(address(mockMimVault), "vMIM");
        vm.label(address(mockMeadVault), "vMEAD");
        vm.label(address(diamond), "BurveDiamond");

        // Fund test contract with tokens
        deal(address(honey), address(this), INITIAL_MINT_AMOUNT);
        deal(address(dai), address(this), INITIAL_MINT_AMOUNT);
        deal(address(mim), address(this), INITIAL_MINT_AMOUNT);
        deal(address(mead), address(this), INITIAL_MINT_AMOUNT);

        // Approve tokens for diamond
        honey.approve(address(diamond), type(uint256).max);
        dai.approve(address(diamond), type(uint256).max);
        mim.approve(address(diamond), type(uint256).max);
        mead.approve(address(diamond), type(uint256).max);
    }

    function testAddLiquidityMimHoney() public {
        // Start acting as the deployer
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        vm.startPrank(deployer);

        // Fund the deployer with tokens
        deal(address(mim), deployer, INITIAL_MINT_AMOUNT);
        deal(address(honey), deployer, INITIAL_MINT_AMOUNT);

        // Create LP token instance for MIM-HONEY pair (closure ID 5)
        BurveMultiLPToken lpToken = BurveMultiLPToken(
            0x544C8dC7445eaF82EAfc24015137D9eD588A3984
        );

        // Print initial balances
        console.log("Initial MIM balance:", mim.balanceOf(deployer));
        console.log("Initial HONEY balance:", honey.balanceOf(deployer));
        console.log("Initial LP token balance:", lpToken.balanceOf(deployer));

        // Prepare amounts for liquidity provision
        uint128[] memory amounts = new uint128[](4);
        amounts[0] = uint128(INITIAL_DEPOSIT_AMOUNT); // HONEY amount
        amounts[1] = 0;
        amounts[2] = uint128(INITIAL_DEPOSIT_AMOUNT); // MIM amount
        amounts[3] = 0;

        // Approve LP token to spend our tokens
        mim.approve(address(lpToken), type(uint256).max);
        honey.approve(address(lpToken), type(uint256).max);

        // Add liquidity
        uint256 shares = lpToken.mintWithMultipleTokens(
            deployer,
            deployer,
            amounts
        );

        // Print final balances
        console.log("Shares received:", shares);
        console.log("Final MIM balance:", mim.balanceOf(deployer));
        console.log("Final HONEY balance:", honey.balanceOf(deployer));
        console.log("Final LP token balance:", lpToken.balanceOf(deployer));

        // Verify we received shares
        assertGt(shares, 0, "Should have received LP shares");
        assertEq(
            lpToken.balanceOf(deployer),
            shares,
            "LP token balance should match shares"
        );

        vm.stopPrank();
    }
}
