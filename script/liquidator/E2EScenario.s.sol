// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {DealScript} from "./ScriptBase.sol";
import {BurveLender} from "../../src/integrations/lender/BurveLender.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MockAggregator} from "./MockAggregator.sol";
import {PositionHelper} from "./PositionHelper.sol";

/// @title E2EScenario
/// @notice All-in-one script: deploy, create positions, crash oracle, liquidate.
///
/// Runs the complete liquidation scenario on an Anvil fork:
///   1. Deploy BurveLender + mock oracles (all $1.00)
///   2. Seed lending pools with liquidity
///   3. Create a healthy position (10% LTV)
///   4. Create a near-max position (75% LTV — liquidation target)
///   5. Crash non-borrow token oracle to $0.10
///   6. Liquidate the unhealthy position
///   7. Verify: position cleared, healthy position untouched
///
/// Usage (simulation — cheatcodes require no-broadcast):
///   forge script script/liquidator/E2EScenario.s.sol \
///     --rpc-url http://127.0.0.1:8545 -vvv
contract E2EScenario is DealScript {
    address constant DIAMOND = 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;

    BurveLender lender;
    PositionHelper helper;
    MockAggregator[] oracles;
    address[] tokens;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        tokens = IBurveMultiSimplex(DIAMOND).getTokens();

        // ============================================================
        //  Step 1: Deploy
        // ============================================================
        console2.log("=== STEP 1: Deploy ===");

        vm.startBroadcast(pk);

        lender = new BurveLender(address(0xDEAD));
        helper = new PositionHelper(DIAMOND);
        console2.log("BurveLender:", address(lender));
        console2.log("PositionHelper:", address(helper));

        for (uint256 i = 0; i < tokens.length; i++) {
            MockAggregator oracle = new MockAggregator(1e8, 8);
            oracles.push(oracle);
            lender.setPriceFeed(tokens[i], address(oracle), 18);
        }
        console2.log("Oracles deployed (all $1.00)");

        vm.stopBroadcast();

        // ============================================================
        //  Step 2: Seed lending pools (deal outside broadcast)
        // ============================================================
        console2.log("");
        console2.log("=== STEP 2: Seed Lending Pools ===");

        uint256 lpAmount = 50_000e18;
        for (uint256 i = 0; i < tokens.length && i < 3; i++) {
            _deal(tokens[i], deployer, lpAmount);
        }

        vm.startBroadcast(pk);
        for (uint256 i = 0; i < tokens.length && i < 3; i++) {
            IERC20(tokens[i]).approve(address(lender), lpAmount);
            lender.depositLiquidity(tokens[i], lpAmount);
            console2.log("  Pool seeded:", i);
        }
        vm.stopBroadcast();

        // ============================================================
        //  Step 3: Create healthy position (10% LTV)
        // ============================================================
        console2.log("");
        console2.log("=== STEP 3: Healthy Position ===");

        uint128 depositValue = 200e18;
        // Fund helper with tokens (cheatcode, outside broadcast)
        for (uint256 i = 0; i < tokens.length; i++) {
            if ((1 << i) & 3 > 0) {
                _deal(tokens[i], address(helper), uint256(depositValue) * 2);
            }
        }

        vm.startBroadcast(pk);
        uint256 posHealthy = helper.createPosition(address(lender), 3, depositValue, tokens[0], 10);
        _logPosition("Healthy", posHealthy);
        vm.stopBroadcast();

        // ============================================================
        //  Step 4: Create near-max LTV position (75%)
        // ============================================================
        console2.log("");
        console2.log("=== STEP 4: Liquidation Target ===");

        for (uint256 i = 0; i < tokens.length; i++) {
            if ((1 << i) & 3 > 0) {
                _deal(tokens[i], address(helper), uint256(depositValue) * 2);
            }
        }

        vm.startBroadcast(pk);
        uint256 posTarget = helper.createPosition(address(lender), 3, depositValue, tokens[0], 75);
        _logPosition("Target (75% LTV)", posTarget);

        // ============================================================
        //  Step 5: Crash oracle
        // ============================================================
        console2.log("");
        console2.log("=== STEP 5: Crash Oracle ===");

        // Crash the NON-BORROW token oracle. We borrow token[0], so crashing
        // token[1] reduces collateral without reducing debt.
        oracles[1].setPrice(0.10e8);
        console2.log("Oracle 1 -> $0.10");

        _logPosition("Healthy (after crash)", posHealthy);
        _logPosition("Target (after crash)", posTarget);

        // ============================================================
        //  Step 6: Liquidate
        // ============================================================
        console2.log("");
        console2.log("=== STEP 6: Liquidate ===");

        uint256 hfTarget = lender.healthFactor(posTarget);
        console2.log("Target HF:", hfTarget);

        if (hfTarget < 1e18) {
            address[] memory debtTokens = new address[](1);
            debtTokens[0] = tokens[0];
            bytes[MAX_TOKENS] memory txData;

            lender.liquidate(posTarget, txData, debtTokens);
            console2.log("Liquidation executed!");
        } else {
            console2.log("Position still healthy, skipping");
        }

        // ============================================================
        //  Step 7: Verify
        // ============================================================
        console2.log("");
        console2.log("=== STEP 7: Final State ===");

        (,,,,uint256 depHealthy,) = lender.positions(posHealthy);
        (,,,,uint256 depTarget,) = lender.positions(posTarget);

        console2.log("Healthy position value:", depHealthy);
        console2.log("Target position value: ", depTarget);

        vm.stopBroadcast();
    }

    function _logPosition(string memory label, uint256 positionId) internal view {
        uint256 colUSD = lender.collateralValueUSD(positionId);
        uint256 debtUSD = lender.borrowValueUSD(positionId);
        uint256 hf = lender.healthFactor(positionId);
        console2.log(label);
        console2.log("  Collateral:", colUSD / 1e18, "USD");
        console2.log("  Debt:      ", debtUSD / 1e18, "USD");
        console2.log("  HF:        ", hf);
    }
}
