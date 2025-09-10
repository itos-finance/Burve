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
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {IBurveMultiValue} from "../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {IBurveMultiSwap} from "../../src/multi/interfaces/IBurveMultiSwap.sol";

contract BRC20ForkTest is ForkableTest, RFTPayer, Auto165 {
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
        opener = new Opener(0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7); // Berachain router

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
        // selectors[1] = ValueFacet.setClosureFees.selector;
        // selectors[2] = ValueFacet.setProtocolEarnings.selector;
        // selectors[3] = ValueFacet.getVertex.selector;

        cuts[0] = (
            IDiamond.FacetCut({
                facetAddress: address(new ValueFacet()),
                action: IDiamond.FacetCutAction.Replace,
                functionSelectors: selectors
            })
        );

        DiamondCutFacet cutFacet = DiamondCutFacet(diamond);

        // prank as the multisig
        vm.startPrank(address(0x9293f9FFC43F6fce06290285919541E963D87F51));
        BaseAdminFacet(BURVE_POOL).acceptOwnership();
        cutFacet.diamondCut(cuts, address(0), "");
        vm.stopPrank();
    }

    function testForkSetup() public view forkOnly {
        assertEq(address(pool), BURVE_POOL);
        assertEq(address(simplex), BURVE_POOL);

        assertEq(address(brc20.pool()), BURVE_POOL);
        assertEq(brc20.closureId(), CLOSURE_ID);
        assertEq(brc20.polVault(), address(0));
        assertEq(brc20.feeTakeX64(), 0);

        assertEq(address(polBRC20.pool()), BURVE_POOL);
        assertEq(polBRC20.closureId(), CLOSURE_ID);
        assertEq(polBRC20.polVault(), TEST_POL_VAULT);
        assertEq(polBRC20.feeTakeX64(), TEST_FEE_TAKE_X64);

        assertEq(opener.router(), 0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7);

        console2.log("Fork setup completed successfully");
    }

    function testPoolTokenAccess() public view forkOnly {
        // Test that we can access pool tokens
        address[] memory tokens = simplex.getTokens();
        assertGt(tokens.length, 0);

        // Check if our target tokens are in the pool
        bool hasUSDC = false;
        bool hasUSDT = false;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == USDC) hasUSDC = true;
            if (tokens[i] == USDT) hasUSDT = true;
        }

        console2.log("Pool contains USDC:", hasUSDC);
        console2.log("Pool contains USDT:", hasUSDT);
    }

    function testBRC20MintValue() public forkOnly {
        uint128 mintValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        uint256[MAX_TOKENS] memory requiredBalances = brc20.addValue(
            address(this),
            0,
            mintValue,
            0,
            amountLimits
        );

        uint256 shares = brc20.balanceOf(address(this));
        assertEq(mintValue, shares);

        uint256[MAX_TOKENS] memory requiredBalances2 = brc20.addValue(
            address(this),
            0,
            mintValue,
            0,
            amountLimits
        );

        assertEq(brc20.balanceOf(address(this)), shares + shares);
        assertEq(brc20.totalShares(), shares + shares);

        for (uint256 i = 0; i < requiredBalances.length; i++) {
            assertEq(requiredBalances[i], requiredBalances2[i]);
        }
    }

    function testBRC20BurnValue() public forkOnly {
        uint128 mintValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        uint256[MAX_TOKENS] memory requiredBalances = brc20.addValue(
            address(this),
            0,
            mintValue,
            0,
            amountLimits
        );

        uint256 shares = brc20.balanceOf(address(this));

        uint256[MAX_TOKENS] memory receivedBalances = brc20.removeValue(
            address(this),
            0,
            uint128(shares),
            0,
            amountLimits
        );

        for (uint256 i = 0; i < requiredBalances.length; i++) {
            assertApproxEqAbs(requiredBalances[i], receivedBalances[i], 1);
        }
        assertEq(brc20.balanceOf(address(this)), 0);
        assertEq(brc20.totalShares(), 0);
    }

    function testBRC20ValueSingle() public forkOnly {
        uint128 value = 1e18;

        // mint
        uint256 requiredBalanceUSDC = brc20.addValueSingle(
            address(this),
            0,
            value,
            0,
            USDC,
            0
        );

        uint256 requiredBalanceUSDT = brc20.addValueSingle(
            address(this),
            0,
            value,
            0,
            USDT,
            0
        );

        // burn
        uint256 removedBalanceUSDC = brc20.removeValueSingle(
            address(this),
            0,
            value,
            0,
            USDC,
            0
        );
        uint256 removedBalanceUSDT = brc20.removeValueSingle(
            address(this),
            0,
            value,
            0,
            USDT,
            0
        );

        /// note: if this is failing, we have a very low amount of liquidity
        assertApproxEqAbs(
            requiredBalanceUSDC + requiredBalanceUSDT,
            removedBalanceUSDC + removedBalanceUSDT,
            1000
        );
        assertEq(brc20.balanceOf(address(this)), 0);
        assertEq(brc20.totalShares(), 0);
    }

    function testBRC20SingleForValue() public forkOnly {
        uint128 amount = 1e6;

        // mint
        uint256 valueReceivedUSDC = brc20.addSingleForValue(
            address(this),
            0,
            USDC,
            amount,
            0,
            0
        );

        uint256 valueReceivedUSDT = brc20.addSingleForValue(
            address(this),
            0,
            USDT,
            amount,
            0,
            0
        );

        // burn
        uint256 valueGivenUSDC = brc20.removeSingleForValue(
            address(this),
            0,
            USDC,
            amount,
            0,
            0
        );
        uint256 valueGivenUSDT = brc20.removeSingleForValue(
            address(this),
            0,
            USDT,
            amount - 1e5,
            0,
            0
        );

        assertApproxEqAbs(valueReceivedUSDC, valueGivenUSDC, 1e15); // lose very little value
        assertApproxEqAbs(valueReceivedUSDT, valueGivenUSDT, 1e17); // lose about 10 cents in value
    }

    function testCompound() public forkOnly {
        uint128 mintValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        brc20.addValue(address(this), 0, mintValue, 0, amountLimits);

        IBurveMultiSwap(BURVE_POOL).swap(
            address(this),
            USDC,
            USDT,
            100e6,
            0,
            3
        );

        brc20.collectEarnings(address(0), 0);
    }

    function testPOLVault() public forkOnly {
        uint128 mintValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        polBRC20.addValue(address(this), 0, mintValue, 0, amountLimits);

        IBurveMultiSwap(BURVE_POOL).swap(
            address(this),
            USDC,
            USDT,
            100e6,
            0,
            3
        );

        (uint256[MAX_TOKENS] memory collectedBalances, ) = polBRC20
            .collectEarnings(address(0), 0);

        uint256 vaultTake = IERC20(USDC).balanceOf(TEST_POL_VAULT);

        assertApproxEqAbs(collectedBalances[0] / 2, vaultTake, 1);
    }

    // New tests for Opener integration
    function testOpenerMintWithUSDC() public forkOnly {
        uint256 mintAmount = 1000e6; // 1000 USDC
        bytes[MAX_TOKENS] memory txData;
        uint256[MAX_TOKENS] memory minSpend;
        uint256 minValueReceived = 0;

        // Deal USDC to this contract
        deal(USDC, address(this), mintAmount);

        // Approve opener to spend USDC
        IERC20(USDC).approve(address(opener), mintAmount);

        // Call opener.mint to add value through USDC
        uint256 addedValue = opener.mint(
            address(polBRC20), // pool (BRC20 contract)
            USDC, // inToken
            mintAmount, // inAmount
            txData, // txData (empty for now)
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
        bytes[MAX_TOKENS] memory txData;
        uint256[MAX_TOKENS] memory minSpend;
        uint256 minValueReceived = 0;

        // Deal USDT to this contract
        deal(USDT, address(this), mintAmount);

        // Approve opener to spend USDT
        IERC20(USDT).approve(address(opener), mintAmount);

        // Call opener.mint to add value through USDT
        uint256 addedValue = opener.mint(
            address(polBRC20), // pool (BRC20 contract)
            USDT, // inToken
            mintAmount, // inAmount
            txData, // txData (empty for now)
            CLOSURE_ID, // closureId
            0, // bgtPercentX256 (0% BGT)
            minSpend, // minSpend
            minValueReceived // minValueReceived
        );

        console2.log("Added value through opener:", addedValue);
        assertGt(addedValue, 0, "Should have added some value");
    }

    function testOpenerWithSwapData() public forkOnly {
        uint256 mintAmount = 1000e6; // 1000 USDC
        bytes[MAX_TOKENS] memory txData;
        uint256[MAX_TOKENS] memory minSpend;
        uint256 minValueReceived = 0;

        // Create swap data for USDC to USDT (this would normally come from oogabooga)
        // For now, we'll use empty data to test the basic flow
        bytes memory swapData = ""; // In real usage, this would contain swap calldata

        // Set txData for USDT swap (index 1 if USDT is the second token)
        // This is a simplified example - in practice you'd need to determine the correct index
        txData[1] = swapData; // Assuming USDT is at index 1

        // Deal USDC to this contract
        deal(USDC, address(this), mintAmount);

        // Approve opener to spend USDC
        IERC20(USDC).approve(address(opener), mintAmount);

        // Call opener.mint with swap data
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

        console2.log("Added value through opener with swap:", addedValue);
        assertGt(addedValue, 0, "Should have added some value");
    }

    function testOpenerAndBRC20Integration() public forkOnly {
        uint256 mintAmount = 1000e6; // 1000 USDC
        bytes[MAX_TOKENS] memory txData;
        uint256[MAX_TOKENS] memory minSpend;
        uint256 minValueReceived = 0;

        // Deal USDC to this contract
        deal(USDC, address(this), mintAmount);

        // Approve opener to spend USDC
        IERC20(USDC).approve(address(opener), mintAmount);

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

    function testOpenerSlippageProtection() public forkOnly {
        uint256 mintAmount = 1000e6; // 1000 USDC
        bytes[MAX_TOKENS] memory txData;
        uint256[MAX_TOKENS] memory minSpend;
        uint256 minValueReceived = 1e20; // Very high minimum value (should fail)

        // Deal USDC to this contract
        deal(USDC, address(this), mintAmount);

        // Approve opener to spend USDC
        IERC20(USDC).approve(address(opener), mintAmount);

        // This should revert due to slippage protection
        vm.expectRevert(); // ValueSlippageExceeded error
        opener.mint(
            address(polBRC20),
            USDC,
            mintAmount,
            txData,
            CLOSURE_ID,
            0,
            minSpend,
            minValueReceived
        );
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
