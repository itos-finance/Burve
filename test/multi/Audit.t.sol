// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* Tests written by auditors */

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {DiamondCutFacet} from "Commons/Diamond/facets/DiamondCutFacet.sol";
import {InitLib, BurveFacets} from "../../src/multi/InitLib.sol";
import {SimplexDiamond as BurveDiamond} from "../../src/multi/Diamond.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {LockFacet} from "../../src/multi/facets/LockFacet.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {ValueTokenFacet} from "../../src/multi/facets/ValueTokenFacet.sol";
import {VaultType} from "../../src/multi/vertex/VaultProxy.sol";
import {IAdjustor} from "../../src/integrations/adjustor/IAdjustor.sol";
import {NullAdjustor} from "../../src/integrations/adjustor/NullAdjustor.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract AuditTest is Test {
    /* Deployer */
    address deployerAddr = makeAddr("Deployer");

    uint256 constant INITIAL_MINT_AMOUNT = 1e30;
    uint128 constant INITIAL_VALUE = 1_000_000e18;

    /* Diamond */
    address public diamond;
    ValueFacet public valueFacet;
    ValueTokenFacet public valueTokenFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;
    LockFacet public lockFacet;
    MockERC20 public USDC;
    MockERC20 public WETH;
    MockERC20 public WBTC;
    MockERC20 public tokenWithMoreDecimals;

    MockERC4626 public USDC_Vault;
    MockERC4626 public WETH_Vault;
    MockERC4626 public WBTC_Vault;
    MockERC4626 public tokenWithMoreDecimals_Vault;

    /* Test Tokens */
    address[] public tokens;
    MockERC4626[] public vaults;

    function setUp() public {
        vm.startPrank(deployerAddr);
        BurveFacets memory facets = InitLib.deployFacets();
        diamond = address(new BurveDiamond(facets, "ValueToken", "BVT"));
        console2.log("Burve deployed at:", diamond);

        valueFacet = ValueFacet(diamond);
        valueTokenFacet = ValueTokenFacet(diamond);
        simplexFacet = SimplexFacet(diamond);
        swapFacet = SwapFacet(diamond);
        lockFacet = LockFacet(diamond);

        USDC = new MockERC20("USDC", "USDC", 6);
        WETH = new MockERC20("WETH", "WETH", 18);
        WBTC = new MockERC20("WBTC", "WBTC", 8);
        tokenWithMoreDecimals = new MockERC20(
            "Token With More Decimals",
            "TWD",
            20
        );

        deal(address(USDC), address(deployerAddr), 10000000e6);
        deal(address(WETH), address(deployerAddr), 10000000e18);
        deal(address(WBTC), address(deployerAddr), 10000000e8);
        deal(
            address(tokenWithMoreDecimals),
            address(deployerAddr),
            10000000e20
        );

        vm.label(address(USDC), "USDC");
        vm.label(address(WETH), "WETH");
        vm.label(address(WBTC), "WBTC");
        vm.label(address(tokenWithMoreDecimals), "Token With More Decimals");

        USDC_Vault = new MockERC4626(USDC, "USDC Vault", "USDC_Vault");
        WETH_Vault = new MockERC4626(WETH, "WETH Vault", "WETH_Vault");
        WBTC_Vault = new MockERC4626(WBTC, "WBTC Vault", "WBTC_Vault");
        tokenWithMoreDecimals_Vault = new MockERC4626(
            tokenWithMoreDecimals,
            "Token With More Decimals Vault",
            "TWD_Vault"
        );

        vm.label(address(USDC_Vault), "USDC_Vault");
        vm.label(address(WETH_Vault), "WETH_Vault");
        vm.label(address(WBTC_Vault), "WBTC_Vault");
        vm.label(
            address(tokenWithMoreDecimals_Vault),
            "Token With More Decimals Vault"
        );

        simplexFacet.addVertex(
            address(USDC),
            address(USDC_Vault),
            VaultType.E4626
        );
        simplexFacet.addVertex(
            address(WETH),
            address(WETH_Vault),
            VaultType.E4626
        );
        simplexFacet.addVertex(
            address(WBTC),
            address(WBTC_Vault),
            VaultType.E4626
        );
        simplexFacet.addVertex(
            address(tokenWithMoreDecimals),
            address(tokenWithMoreDecimals_Vault),
            VaultType.E4626
        );

        USDC.approve(address(diamond), type(uint256).max);
        WETH.approve(address(diamond), type(uint256).max);
        WBTC.approve(address(diamond), type(uint256).max);
        tokenWithMoreDecimals.approve(address(diamond), type(uint256).max);

        uint256 oneX128 = 1 << 128;
        uint128 baseFeeX128 = uint128(oneX128 / 1000);
        simplexFacet.addClosure(1, INITIAL_VALUE, baseFeeX128, 0);
        simplexFacet.addClosure(2, INITIAL_VALUE, baseFeeX128, 0);
        simplexFacet.addClosure(3, INITIAL_VALUE, baseFeeX128, 0);
        simplexFacet.addClosure(4, INITIAL_VALUE, baseFeeX128, 0);
        simplexFacet.addClosure(5, INITIAL_VALUE, baseFeeX128, 0);
        simplexFacet.addClosure(6, INITIAL_VALUE, baseFeeX128, 0);
        simplexFacet.addClosure(7, INITIAL_VALUE, baseFeeX128, 0);
        simplexFacet.addClosure(15, INITIAL_VALUE, baseFeeX128, 0);

        vm.stopPrank();
    }

    function testHowRemoveSingleForValueWorks() public {
        deal(address(USDC), address(this), 10000000e6);
        deal(address(WETH), address(this), 10000000e18);
        deal(address(WBTC), address(this), 10000000e8);
        deal(address(tokenWithMoreDecimals), address(this), 10000000e20);

        USDC.approve(address(diamond), type(uint256).max);
        WETH.approve(address(diamond), type(uint256).max);
        WBTC.approve(address(diamond), type(uint256).max);
        tokenWithMoreDecimals.approve(address(diamond), type(uint256).max);

        valueFacet.addValue(address(this), 15, 100e18, 0);

        valueFacet.removeSingleForValue(
            address(this),
            15,
            address(USDC),
            99e6,
            0,
            0
        );
        vm.expectRevert();
        valueFacet.removeSingleForValue(
            address(this),
            15,
            address(WETH),
            10e18,
            0,
            0
        );
        vm.expectRevert();
        valueFacet.removeSingleForValue(
            address(this),
            15,
            address(WBTC),
            9e8,
            0,
            0
        );
        vm.expectRevert();
        valueFacet.removeSingleForValue(
            address(this),
            15,
            address(tokenWithMoreDecimals),
            10e20,
            0,
            0
        );
        valueFacet.removeSingleForValue(
            address(this),
            15,
            address(WBTC),
            8.9e7,
            0,
            0
        );
    }
}
