// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "Commons/Math/Cast.sol";
import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {ForkableTest} from "Commons/Test/ForkableTest.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {DiamondCutFacet} from "Commons/Diamond/facets/DiamondCutFacet.sol";
import {RFTPayer} from "Commons/Util/RFT.sol";
import {Auto165} from "Commons/ERC/Auto165.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";

import {BRC20} from "../../src/integrations/BRC20.sol";
import {Opener} from "../../src/integrations/opener/Opener.sol";
import {IOBRouter} from "../../src/integrations/opener/IOBRouter.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {IBurveMultiValue} from "../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {IBurveMultiSwap} from "../../src/multi/interfaces/IBurveMultiSwap.sol";

contract FBRC20OpenerTest is ForkableTest, RFTPayer, Auto165 {
    // Live Burve pool address on Berachain
    address public constant BURVE_POOL =
        0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;

    // Closure ID to test with
    uint16 public constant CLOSURE_ID = 3;

    // Token addresses from usd.json
    address public constant USDC = 0x549943e04f40284185054145c6E4e9568C1D3241;
    address public constant USDT = 0x779Ded0c9e1022225f8E0630b35a9b54bE713736;

    // BRC20 contract instance
    BRC20 public brc20;
    BRC20 public polBRC20;

    // Opener contract instance
    Opener public opener;

    // Pool interfaces
    IBurveMultiValue public pool;
    IBurveMultiSimplex public simplex;

    // Token instances
    IERC20 public usdc;
    IERC20 public usdt;

    // Test addresses for PoL vault
    address public constant TEST_POL_VAULT = address(1234);
    uint256 public constant TEST_FEE_TAKE_X64 = 9223372036854775808; // 50%

    function preSetup() internal override {}

    function deploySetup() internal override {
        // This will run when not forking (local testing)
        // Deploy mock contracts for local testing
        _deployLocalSetup();
    }

    function forkSetup() internal override {
        // This will run when forking from Berachain
        _setupFork();
    }

    function _deployLocalSetup() internal {
        // Mock setup for local testing
        // This would deploy local versions of the contracts
    }

    function _setupFork() internal {
        // Set up the fork environment
        pool = IBurveMultiValue(BURVE_POOL);
        simplex = IBurveMultiSimplex(BURVE_POOL);

        // Initialize token instances
        usdc = IERC20(USDC);
        usdt = IERC20(USDT);

        // Deploy Opener contract
        // opener = new Opener(0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7); // Berachain router

        // use the one deployed onchain
        opener = Opener(0xaBa9D5ce40a81Da22526092FE4bA0517DeF2FBD3);

        // Deploy BRC20 contract (no PoL vault)
        brc20 = new BRC20(
            "Burve BRC20",
            "bBRC20",
            BURVE_POOL,
            CLOSURE_ID,
            address(0), // no PoL vault
            0 // no fee take
        );

        // Deploy BRC20 contract with PoL vault
        polBRC20 = new BRC20(
            "Burve BRC20 PoL",
            "bBRC20PoL",
            BURVE_POOL,
            CLOSURE_ID,
            TEST_POL_VAULT,
            TEST_FEE_TAKE_X64 // 50% fee take
        );

        console2.log("BRC20 deployed at:", address(brc20));
        console2.log("PoL BRC20 deployed at:", address(polBRC20));
        console2.log("Opener deployed at:", address(opener));
        console2.log("Pool address:", BURVE_POOL);
        console2.log("Closure ID:", CLOSURE_ID);

        // Log token information
        console2.log("USDC address:", USDC);
        console2.log("USDT address:", USDT);

        // Log pool state
        address[] memory tokens = simplex.getTokens();
        console2.log("Pool has", tokens.length, "tokens");
        for (uint256 i = 0; i < tokens.length; i++) {
            console2.log("Token", i, ":", tokens[i]);
        }

        _cutValueFacet(BURVE_POOL);
    }

    /// TODO: note before this shares contract will be operational,
    /// we need to facet cut to add data to the collect calls
    function _cutValueFacet(address diamond) public {
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ValueFacet.collectEarnings.selector;

        cuts[0] = (
            IDiamond.FacetCut({
                facetAddress: address(new ValueFacet()),
                action: IDiamond.FacetCutAction.Replace,
                functionSelectors: selectors
            })
        );

        DiamondCutFacet cutFacet = DiamondCutFacet(diamond);

        // prank as the multisig

        vm.startPrank(address(0x7ABBF47392EcC1C37Be03A7f57ac95EF2c408136));
        // vm.startPrank(address(0x9293f9FFC43F6fce06290285919541E963D87F51));
        // BaseAdminFacet(BURVE_POOL).acceptOwnership(); // We currently have ownership, so we don't need to accept
        cutFacet.diamondCut(cuts, address(0), "");
        vm.stopPrank();
    }

    // ========================================
    // Opener Integration Tests
    // ========================================

    function testOpenerMintWithUSDC() public forkOnly {
        uint256 mintAmount = 200e6; // 200 USDC

        // Deal USDC to this contract
        deal(USDC, address(this), mintAmount);

        // Approve opener to spend USDC
        IERC20(USDC).approve(address(opener), mintAmount);

        // Set up swap info for USDC -> USDT
        IOBRouter.swapTokenInfo memory info = IOBRouter.swapTokenInfo({
            inputToken: USDC,
            inputAmount: 100e6,
            outputToken: USDT,
            outputQuote: 99000000, // Approximate 1:1 ratio with small slippage
            outputMin: 99000000, // 1% slippage tolerance
            outputReceiver: address(0xaBa9D5ce40a81Da22526092FE4bA0517DeF2FBD3)
        });

        // Set up transaction data for the swap
        bytes[MAX_TOKENS] memory txData;
        txData[1] = abi.encodeWithSelector(
            IOBRouter.swap.selector,
            info,
            hex"779Ded0c9e1022225f8E0630b35a9b54bE7137360000000000000000000000000000000000000000000000000000000000000005f511300000000000000000000000000000000000000000000000000000000005f4967d0000000000000000000000000000000000000000000000000000000005f5112f01549943e04f40284185054145c6E4e9568C1D324101ffff01cd1929ee788b25581a2b3ac55a138a14347d3304015d6e64ea5Ea5342693ec45c1d94b45261779B51900", // Empty swap data for testing
            address(0x5d6e64ea5Ea5342693ec45c1d94b45261779B519), // executor
            0 // Empty deadline for testing
        );

        uint256[MAX_TOKENS] memory minSpend;
        uint256 minValueReceived = 0;

        // Call opener.mint to add value through USDC
        uint256 addedValue = opener.mint(
            address(polBRC20), // pool (BRC20 contract)
            USDC, // inToken
            mintAmount, // inAmount
            txData, // txData
            CLOSURE_ID, // closureId
            0, // bgtPercentX256 (0% BGT)
            minSpend, // minSpend
            minValueReceived // minValueReceived
        );

        console2.log("Added value through opener:", addedValue);
        assertGt(addedValue, 0, "Should have added some value");
    }

    function testOpenerMintWithUSDT() public forkOnly {
        uint256 mintAmount = 1000e6; // 1000 USDT

        // Deal USDT to this contract
        deal(USDT, address(this), mintAmount);

        // Approve opener to spend USDT
        IERC20(USDT).approve(address(opener), mintAmount);

        // Set up swap info for USDT -> USDC
        IOBRouter.swapTokenInfo memory info = IOBRouter.swapTokenInfo({
            inputToken: USDT,
            inputAmount: mintAmount,
            outputToken: USDC,
            outputQuote: 999000000, // Approximate 1:1 ratio with small slippage
            outputMin: 990000000, // 1% slippage tolerance
            outputReceiver: address(this)
        });

        // Set up transaction data for the swap
        bytes[MAX_TOKENS] memory txData;
        // Note: In a real scenario, this would be generated by oogabooga/swap.mjs
        // For testing, we'll use empty data to test the basic flow
        txData[0] = abi.encodeWithSelector(
            IOBRouter.swap.selector,
            info,
            hex"d46cadbc000000000000000000000000549943e04f40284185054145c6e4e9568c1d32410000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000779ded0c9e1022225f8e0630b35a9b54be7137360000000000000000000000000000000000000000000000000000000005f4d6e00000000000000000000000000000000000000000000000000000000005e59749000000000000000000000000ed63e871f5de87cb1919671ee9e2d331183eda8f00000000000000000000000000000000000000000000000000000000000001200000000000000000000000005d6e64ea5ea5342693ec45c1d94b45261779b519000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000ba779Ded0c9e1022225f8E0630b35a9b54bE7137360000000000000000000000000000000000000000000000000000000000000005f4d6e00000000000000000000000000000000000000000000000000000000005f491300000000000000000000000000000000000000000000000000000000005f4d6df01549943e04f40284185054145c6E4e9568C1D324101ffff01cd1929ee788b25581a2b3ac55a138a14347d3304015d6e64ea5Ea5342693ec45c1d94b45261779B51900000000000000", // Empty swap data for testing
            address(0xaBa9D5ce40a81Da22526092FE4bA0517DeF2FBD3), // Empty receiver for testing
            0 // Empty deadline for testing
        );

        uint256[MAX_TOKENS] memory minSpend;
        uint256 minValueReceived = 0;

        // Call opener.mint to add value through USDT
        uint256 addedValue = opener.mint(
            address(polBRC20), // pool (BRC20 contract)
            USDT, // inToken
            mintAmount, // inAmount
            txData, // txData
            CLOSURE_ID, // closureId
            0, // bgtPercentX256 (0% BGT)
            minSpend, // minSpend
            minValueReceived // minValueReceived
        );

        console2.log("Added value through opener:", addedValue);
        assertGt(addedValue, 0, "Should have added some value");
    }

    function testOpenerAndBRC20Integration() public forkOnly {
        uint256 mintAmount = 1000e6; // 1000 USDC

        // Deal USDC to this contract
        deal(USDC, address(this), mintAmount);

        // Approve opener to spend USDC
        IERC20(USDC).approve(address(opener), mintAmount);

        // Set up swap info for USDC -> USDT
        IOBRouter.swapTokenInfo memory info = IOBRouter.swapTokenInfo({
            inputToken: USDC,
            inputAmount: mintAmount,
            outputToken: USDT,
            outputQuote: 999000000, // Approximate 1:1 ratio with small slippage
            outputMin: 990000000, // 1% slippage tolerance
            outputReceiver: address(this)
        });

        // Set up transaction data for the swap
        bytes[MAX_TOKENS] memory txData;
        // Note: In a real scenario, this would be generated by oogabooga/swap.mjs
        // For testing, we'll use empty data to test the basic flow
        txData[1] = abi.encodeWithSelector(
            IOBRouter.swap.selector,
            info,
            hex"", // Empty swap data for testing
            address(0), // Empty receiver for testing
            0 // Empty deadline for testing
        );

        uint256[MAX_TOKENS] memory minSpend;
        uint256 minValueReceived = 0;

        // Get initial balances
        uint256 initialUSDCBalance = IERC20(USDC).balanceOf(address(this));
        uint256 initialBRC20Shares = polBRC20.balanceOf(address(this));

        // Add value through opener
        uint256 addedValue = opener.mint(
            address(polBRC20),
            USDC,
            mintAmount,
            txData,
            CLOSURE_ID,
            0,
            minSpend,
            minValueReceived
        );

        // Check that BRC20 shares were minted
        uint256 finalBRC20Shares = polBRC20.balanceOf(address(this));
        assertGt(
            finalBRC20Shares,
            initialBRC20Shares,
            "Should have received BRC20 shares"
        );

        // Check that USDC was spent
        uint256 finalUSDCBalance = IERC20(USDC).balanceOf(address(this));
        assertLt(
            finalUSDCBalance,
            initialUSDCBalance,
            "Should have spent USDC"
        );

        console2.log("Integration test completed:");
        console2.log("Initial USDC balance:", initialUSDCBalance);
        console2.log("Final USDC balance:", finalUSDCBalance);
        console2.log("USDC spent:", initialUSDCBalance - finalUSDCBalance);
        console2.log("Initial BRC20 shares:", initialBRC20Shares);
        console2.log("Final BRC20 shares:", finalBRC20Shares);
        console2.log(
            "BRC20 shares gained:",
            finalBRC20Shares - initialBRC20Shares
        );
        console2.log("Value added:", addedValue);
    }

    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata
    ) external returns (bytes memory) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (requests[i] > 0) {
                deal(tokens[i], address(this), SafeCast.toUint256(requests[i]));
                // minting
                TransferHelper.safeTransfer(
                    tokens[i],
                    msg.sender,
                    SafeCast.toUint256(requests[i])
                );
            }
        }

        return "";
    }
}
