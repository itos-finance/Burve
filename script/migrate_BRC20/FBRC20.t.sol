// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "Commons/Math/Cast.sol";
import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {BurveForkableTest} from "../../test/integrations/Fork.u.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {DiamondCutFacet} from "Commons/Diamond/facets/DiamondCutFacet.sol";
import {RFTPayer} from "Commons/Util/RFT.sol";
import {Auto165} from "Commons/ERC/Auto165.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";

import {BRC20} from "../../src/integrations/BRC20.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {IBurveMultiValue} from "../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {IBurveMultiSwap} from "../../src/multi/interfaces/IBurveMultiSwap.sol";
import {DummyRewarder} from "../../test/mocks/DummyRewarder.sol";

contract FBRC20Test is BurveForkableTest, RFTPayer, Auto165 {
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

    // Dummy rewarder for testing
    DummyRewarder public dummyRewarder;

    // Token instances
    IERC20 public usdc;
    IERC20 public usdt;

    // Test addresses for PoL vault
    address public constant TEST_POL_VAULT = address(1234);
    uint256 public constant TEST_FEE_TAKE_X64 = 9223372036854775808; // 50%

    function forkSetup() internal override {
        // Call parent setup first
        super.forkSetup();

        // Set up BRC20-specific contracts
        _setupBRC20Contracts();
    }

    function _setupBRC20Contracts() internal {
        // Initialize token instances
        usdc = IERC20(USDC);
        usdt = IERC20(USDT);

        // Deploy dummy rewarder
        dummyRewarder = new DummyRewarder();

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
        console2.log("Dummy rewarder deployed at:", address(dummyRewarder));
        console2.log("Pool address:", BURVE_POOL);
        console2.log("Closure ID:", CLOSURE_ID);

        // Log token information
        console2.log("USDC address:", USDC);
        console2.log("USDT address:", USDT);

        // Log pool state
        address[] memory poolTokens = simplexFacet.getTokens();
        console2.log("Pool has", poolTokens.length, "tokens");
        for (uint256 i = 0; i < poolTokens.length; i++) {
            console2.log("Token", i, ":", poolTokens[i]);
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
        vm.startPrank(address(0xEAD30c685F6B4817722018E3205c5f2edD5403DB));
        // BaseAdminFacet(BURVE_POOL).acceptOwnership(); // We currently have ownership, so we don't need to accept
        cutFacet.diamondCut(cuts, address(0), "");
        vm.stopPrank();
    }

    function testForkSetup() public view forkOnly {
        assertEq(diamond, BURVE_POOL);
        assertEq(address(simplexFacet), BURVE_POOL);

        assertEq(address(brc20.pool()), BURVE_POOL);
        assertEq(brc20.closureId(), CLOSURE_ID);
        assertEq(brc20.polVault(), address(0));
        assertEq(brc20.feeTakeX64(), 0);

        assertEq(address(polBRC20.pool()), BURVE_POOL);
        assertEq(polBRC20.closureId(), CLOSURE_ID);
        assertEq(polBRC20.polVault(), TEST_POL_VAULT);
        assertEq(polBRC20.feeTakeX64(), TEST_FEE_TAKE_X64);

        console2.log("Fork setup completed successfully");
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
        uint128 mintValue = 1e25;
        uint256[MAX_TOKENS] memory amountLimits;

        // Mint shares to this contract
        brc20.addValue(address(this), 0, mintValue, 0, amountLimits);

        // Get initial values before swaps
        uint256 initialTotalValue = brc20.totalValue();
        uint256 initialBRC20Shares = brc20.balanceOf(address(this));

        console2.log("Initial total value:", initialTotalValue);
        console2.log("Initial BRC20 shares:", initialBRC20Shares);

        // Perform swaps to generate fees
        IBurveMultiSwap(BURVE_POOL).swap(
            address(this),
            USDC,
            USDT,
            10000e6,
            0,
            3
        );

        IBurveMultiSwap(BURVE_POOL).swap(
            address(this),
            USDT,
            USDC,
            10000e6,
            0,
            3
        );

        // Get balances after swaps but before compound
        uint256 initialUSDCBalance = usdc.balanceOf(address(this));
        uint256 initialUSDTBalance = usdt.balanceOf(address(this));

        console2.log("USDC balance after swaps:", initialUSDCBalance);
        console2.log("USDT balance after swaps:", initialUSDTBalance);

        // Collect earnings - this should trigger compound
        (uint256[MAX_TOKENS] memory collectedBalances, ) = brc20
            .collectEarnings(address(this), 0);

        // Verify that fees were collected for both tokens
        assertGt(collectedBalances[0], 0, "Should have collected USDC fees");
        assertGt(collectedBalances[1], 0, "Should have collected USDT fees");

        console2.log("Collected USDC fees:", collectedBalances[0]);
        console2.log("Collected USDT fees:", collectedBalances[1]);

        // Verify that totalValue increased due to compound
        uint256 finalTotalValue = brc20.totalValue();
        assertGt(
            finalTotalValue,
            initialTotalValue,
            "Total value should have increased due to compound"
        );

        console2.log("Final total value:", finalTotalValue);
        console2.log(
            "Value gained from compound:",
            finalTotalValue - initialTotalValue
        );

        // Verify that BRC20 shares remain the same after compound
        uint256 finalBRC20Shares = brc20.balanceOf(address(this));
        assertEq(
            finalBRC20Shares,
            initialBRC20Shares,
            "BRC20 shares should remain the same after compound"
        );

        console2.log("Final BRC20 shares:", finalBRC20Shares);
        console2.log(
            "Shares change from compound:",
            int256(finalBRC20Shares) - int256(initialBRC20Shares)
        );
    }

    function testPOLVault() public forkOnly {
        uint128 mintValue = 1e25;
        uint256[MAX_TOKENS] memory amountLimits;

        // Mint shares to this contract
        polBRC20.addValue(address(this), 0, mintValue, 0, amountLimits);

        // Get initial values before swaps
        uint256 initialTotalValue = polBRC20.totalValue();
        uint256 initialBRC20Shares = polBRC20.balanceOf(address(this));

        console2.log("Initial total value:", initialTotalValue);
        console2.log("Initial BRC20 shares:", initialBRC20Shares);

        // Perform swaps to generate fees
        IBurveMultiSwap(BURVE_POOL).swap(
            address(this),
            USDC,
            USDT,
            10000e6,
            0,
            3
        );

        IBurveMultiSwap(BURVE_POOL).swap(
            address(this),
            USDT,
            USDC,
            10000e6,
            0,
            3
        );

        // Get balances after swaps but before compound
        uint256 initialUSDCBalance = usdc.balanceOf(address(this));
        uint256 initialUSDTBalance = usdt.balanceOf(address(this));

        console2.log("USDC balance after swaps:", initialUSDCBalance);
        console2.log("USDT balance after swaps:", initialUSDTBalance);

        // Collect earnings - this should trigger compound
        (uint256[MAX_TOKENS] memory collectedBalances, ) = polBRC20
            .collectEarnings(address(this), 0);

        // Verify that fees were collected for both tokens
        assertGt(collectedBalances[0], 0, "Should have collected USDC fees");
        assertGt(collectedBalances[1], 0, "Should have collected USDT fees");

        console2.log("Collected USDC fees:", collectedBalances[0]);
        console2.log("Collected USDT fees:", collectedBalances[1]);

        // Verify that the correct fee take amount was sent to the PoL vault
        uint256 expectedUSDCFeeTake = (collectedBalances[0] *
            TEST_FEE_TAKE_X64) / (1 << 64);
        uint256 expectedUSDTFeeTake = (collectedBalances[1] *
            TEST_FEE_TAKE_X64) / (1 << 64);

        uint256 actualUSDCBalance = usdc.balanceOf(TEST_POL_VAULT);
        uint256 actualUSDTBalance = usdt.balanceOf(TEST_POL_VAULT);

        console2.log("Expected USDC fee take:", expectedUSDCFeeTake);
        console2.log("Actual USDC balance in PoL vault:", actualUSDCBalance);
        console2.log("Expected USDT fee take:", expectedUSDTFeeTake);
        console2.log("Actual USDT balance in PoL vault:", actualUSDTBalance);

        // Allow for small rounding differences
        assertApproxEqRel(
            actualUSDCBalance,
            expectedUSDCFeeTake,
            1,
            "USDC fee take should be approximately correct"
        );
        assertApproxEqRel(
            actualUSDTBalance,
            expectedUSDTFeeTake,
            1,
            "USDT fee take should be approximately correct"
        );

        // Verify that totalValue increased due to compound
        uint256 finalTotalValue = polBRC20.totalValue();
        assertGt(
            finalTotalValue,
            initialTotalValue,
            "Total value should have increased due to compound"
        );

        console2.log("Final total value:", finalTotalValue);
        console2.log(
            "Value gained from compound:",
            finalTotalValue - initialTotalValue
        );

        // Verify that BRC20 shares remain the same after compound
        uint256 finalBRC20Shares = polBRC20.balanceOf(address(this));
        assertEq(
            finalBRC20Shares,
            initialBRC20Shares,
            "BRC20 shares should remain the same after compound"
        );

        console2.log("Final BRC20 shares:", finalBRC20Shares);
        console2.log(
            "Shares change from compound:",
            int256(finalBRC20Shares) - int256(initialBRC20Shares)
        );
    }

    function testFeeTakeChange() public forkOnly {
        console2.log("Testing fee take change functionality");

        // Test that only owner can change fee take
        uint256 newFeeTakeX64 = 4611686018427387904; // 25% fee take

        // Impersonate the not the owner to change the fee take, revert
        vm.startPrank(address(0x1234));
        vm.expectRevert(AdminLib.NotOwner.selector);
        polBRC20.setFeeTake(newFeeTakeX64);
        vm.stopPrank();

        polBRC20.setFeeTake(newFeeTakeX64);

        // Verify the fee take was changed
        assertEq(
            polBRC20.feeTakeX64(),
            newFeeTakeX64,
            "Fee take should be updated"
        );

        console2.log("Original fee take:", TEST_FEE_TAKE_X64);
        console2.log("New fee take:", polBRC20.feeTakeX64());
        console2.log("Fee take change test passed");
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

    // ========================================
    // Rewarder Integration Tests
    // ========================================

    function testRewarderMint() public forkOnly {
        // Set up rewarder
        brc20.setRewarder(address(dummyRewarder));

        uint128 mintValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Reset rewarder counters
        dummyRewarder.reset();

        // Mint shares
        brc20.addValue(address(this), 0, mintValue, 0, amountLimits);

        // Verify rewarder was called
        assertEq(
            dummyRewarder.depositCallCount(),
            1,
            "Should have called onDeposit once"
        );
        assertEq(
            dummyRewarder.withdrawCallCount(),
            0,
            "Should not have called onWithdraw"
        );
        assertEq(
            dummyRewarder.totalDepositAmount(),
            mintValue,
            "Total deposit amount should match"
        );
        assertEq(
            dummyRewarder.totalWithdrawAmount(),
            0,
            "Total withdraw amount should be 0"
        );

        // Verify user-specific data
        (uint256 userDepositCount, uint256 userWithdrawCount) = dummyRewarder
            .getUserCallCount(address(this));
        assertEq(userDepositCount, 1, "User deposit count should be 1");
        assertEq(userWithdrawCount, 0, "User withdraw count should be 0");

        (uint256 userDepositAmount, uint256 userWithdrawAmount) = dummyRewarder
            .getUserAmounts(address(this));
        assertEq(
            userDepositAmount,
            mintValue,
            "User deposit amount should match"
        );
        assertEq(userWithdrawAmount, 0, "User withdraw amount should be 0");

        console2.log("Rewarder integration mint test passed");
    }

    function testRewarderBurn() public forkOnly {
        // Set up rewarder
        brc20.setRewarder(address(dummyRewarder));

        uint128 mintValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // First mint some shares
        brc20.addValue(address(this), 0, mintValue, 0, amountLimits);

        // Reset rewarder counters for clean test
        dummyRewarder.reset();

        // Burn all shares
        uint256 shares = brc20.balanceOf(address(this));
        brc20.removeValue(address(this), 0, uint128(shares), 0, amountLimits);

        // Verify rewarder was called
        assertEq(
            dummyRewarder.depositCallCount(),
            0,
            "Should not have called onDeposit"
        );
        assertEq(
            dummyRewarder.withdrawCallCount(),
            1,
            "Should have called onWithdraw once"
        );
        assertEq(
            dummyRewarder.totalDepositAmount(),
            0,
            "Total deposit amount should be 0"
        );
        assertEq(
            dummyRewarder.totalWithdrawAmount(),
            shares,
            "Total withdraw amount should match shares"
        );

        // Verify user-specific data
        (uint256 userDepositCount, uint256 userWithdrawCount) = dummyRewarder
            .getUserCallCount(address(this));
        assertEq(userDepositCount, 0, "User deposit count should be 0");
        assertEq(userWithdrawCount, 1, "User withdraw count should be 1");

        (uint256 userDepositAmount, uint256 userWithdrawAmount) = dummyRewarder
            .getUserAmounts(address(this));
        assertEq(userDepositAmount, 0, "User deposit amount should be 0");
        assertEq(
            userWithdrawAmount,
            shares,
            "User withdraw amount should match shares"
        );
    }

    function testRewarderTransfer() public forkOnly {
        // Set up rewarder
        brc20.setRewarder(address(dummyRewarder));

        uint128 mintValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;
        address recipient = address(0x1234);

        // Mint shares to this contract
        brc20.addValue(address(this), 0, mintValue, 0, amountLimits);

        // Reset rewarder counters for clean test
        dummyRewarder.reset();

        // Transfer shares to another address
        uint256 transferAmount = mintValue / 2;
        brc20.transfer(recipient, transferAmount);

        // Verify rewarder was called for both deposit and withdraw
        assertEq(
            dummyRewarder.depositCallCount(),
            1,
            "Should have called onDeposit once for recipient"
        );
        assertEq(
            dummyRewarder.withdrawCallCount(),
            1,
            "Should have called onWithdraw once for sender"
        );
        assertEq(
            dummyRewarder.totalDepositAmount(),
            transferAmount,
            "Total deposit amount should match transfer"
        );
        assertEq(
            dummyRewarder.totalWithdrawAmount(),
            transferAmount,
            "Total withdraw amount should match transfer"
        );

        // Verify sender data
        (
            uint256 senderDepositCount,
            uint256 senderWithdrawCount
        ) = dummyRewarder.getUserCallCount(address(this));
        assertEq(senderDepositCount, 0, "Sender deposit count should be 0");
        assertEq(senderWithdrawCount, 1, "Sender withdraw count should be 1");

        // Verify recipient data
        (
            uint256 recipientDepositCount,
            uint256 recipientWithdrawCount
        ) = dummyRewarder.getUserCallCount(recipient);
        assertEq(
            recipientDepositCount,
            1,
            "Recipient deposit count should be 1"
        );
        assertEq(
            recipientWithdrawCount,
            0,
            "Recipient withdraw count should be 0"
        );
    }

    function testRewarderMultipleOperations() public forkOnly {
        // Set up rewarder
        brc20.setRewarder(address(dummyRewarder));

        uint128 mintValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;
        address recipient1 = address(0x1234);
        address recipient2 = address(0x5678);

        // Reset rewarder counters
        dummyRewarder.reset();

        // Multiple operations
        brc20.addValue(address(this), 0, mintValue, 0, amountLimits); // Mint
        brc20.addValue(recipient1, 0, mintValue, 0, amountLimits); // Mint to recipient1
        brc20.transfer(recipient2, mintValue / 2); // Transfer to recipient2
        brc20.removeValue(
            address(this),
            0,
            uint128(mintValue / 2),
            0,
            amountLimits
        ); // Burn

        // Verify total counts
        assertEq(
            dummyRewarder.depositCallCount(),
            3,
            "Should have called onDeposit 3 times"
        );
        assertEq(
            dummyRewarder.withdrawCallCount(),
            2,
            "Should have called onWithdraw 2 times"
        );
        assertEq(
            dummyRewarder.getTotalCallCount(),
            5,
            "Total call count should be 5"
        );

        // Verify individual user counts
        (uint256 userDepositCount, uint256 userWithdrawCount) = dummyRewarder
            .getUserCallCount(address(this));
        assertEq(
            userDepositCount,
            1,
            "This contract should have 1 deposit call"
        );
        assertEq(
            userWithdrawCount,
            2,
            "This contract should have 2 withdraw calls"
        );

        (
            uint256 recipient1DepositCount,
            uint256 recipient1WithdrawCount
        ) = dummyRewarder.getUserCallCount(recipient1);
        assertEq(
            recipient1DepositCount,
            1,
            "Recipient1 should have 1 deposit call"
        );
        assertEq(
            recipient1WithdrawCount,
            0,
            "Recipient1 should have 0 withdraw calls"
        );

        (
            uint256 recipient2DepositCount,
            uint256 recipient2WithdrawCount
        ) = dummyRewarder.getUserCallCount(recipient2);
        assertEq(
            recipient2DepositCount,
            1,
            "Recipient2 should have 1 deposit call"
        );
        assertEq(
            recipient2WithdrawCount,
            0,
            "Recipient2 should have 0 withdraw calls"
        );
    }

    function testRewarderNoRewarder() public forkOnly {
        // Test that operations work without a rewarder set
        uint128 mintValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Ensure no rewarder is set
        assertEq(
            brc20.rewarder(),
            address(0),
            "Rewarder should not be set initially"
        );

        // Operations should work without rewarder
        brc20.addValue(address(this), 0, mintValue, 0, amountLimits);
        uint256 shares = brc20.balanceOf(address(this));
        assertEq(shares, mintValue, "Shares should be minted correctly");

        brc20.removeValue(address(this), 0, uint128(shares), 0, amountLimits);
        assertEq(
            brc20.balanceOf(address(this)),
            0,
            "Shares should be burned correctly"
        );
    }

    function testClosePositionAndGetTokensBack() public forkOnly {
        console2.log("Testing position closure and token return");

        uint128 mintValue = 1e18;
        uint256[MAX_TOKENS] memory amountLimits;

        // Open position by adding value
        uint256[MAX_TOKENS] memory requiredBalances = brc20.addValue(
            address(this),
            0,
            mintValue,
            0,
            amountLimits
        );

        uint256 shares = brc20.balanceOf(address(this));
        assertEq(shares, mintValue, "Should have correct number of shares");
        assertGt(shares, 0, "Should have some shares");

        console2.log("Shares after opening position:", shares);
        console2.log("Required USDC for position:", requiredBalances[0]);
        console2.log("Required USDT for position:", requiredBalances[1]);

        // Close position by removing all value
        uint256[MAX_TOKENS] memory receivedBalances = brc20.removeValue(
            address(this),
            0,
            uint128(shares),
            0,
            amountLimits
        );

        // Verify we got our shares back
        assertEq(
            brc20.balanceOf(address(this)),
            0,
            "Should have no shares after closing"
        );
        assertEq(brc20.totalShares(), 0, "Total shares should be zero");

        console2.log("Received USDC when closing:", receivedBalances[0]);
        console2.log("Received USDT when closing:", receivedBalances[1]);

        // Verify we got our tokens back (allowing for small rounding differences)
        for (uint256 i = 0; i < requiredBalances.length; i++) {
            if (requiredBalances[i] > 0) {
                assertApproxEqAbs(
                    requiredBalances[i],
                    receivedBalances[i],
                    1,
                    string(
                        abi.encodePacked(
                            "Token ",
                            i,
                            " should be returned with minimal loss"
                        )
                    )
                );
            }
        }

        // Verify final token balances are approximately restored
        uint256 finalUSDCBalance = usdc.balanceOf(address(this));
        uint256 finalUSDTBalance = usdt.balanceOf(address(this));

        console2.log("Final USDC balance:", finalUSDCBalance);
        console2.log("Final USDT balance:", finalUSDTBalance);

        // Check that we got most of our tokens back (allowing for small slippage)
        assertApproxEqAbs(
            finalUSDCBalance,
            receivedBalances[0],
            1, // Allow for small differences due to slippage
            "USDC balance should be approximately restored"
        );
        assertApproxEqAbs(
            finalUSDTBalance,
            receivedBalances[1],
            1, // Allow for small differences due to slippage
            "USDT balance should be approximately restored"
        );

        console2.log("Position closure test passed - tokens properly returned");
    }
}
