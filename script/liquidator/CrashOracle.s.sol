// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BurveLender} from "../../src/integrations/lender/BurveLender.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {MockAggregator} from "./MockAggregator.sol";

/// @title CrashOracle
/// @notice Crash a mock oracle price to trigger liquidation on Anvil.
///
/// Sets the oracle for tokens[0] (first pool token) to $0.50, which halves
/// the collateral value of positions holding that token, pushing near-max-LTV
/// positions below the liquidation threshold.
///
/// Env vars:
///   DEPLOYER_PRIVATE_KEY — Anvil account private key (oracle owner)
///   BURVE_LENDER — Address of deployed BurveLender
///   CRASH_PRICE — (optional) New price in Chainlink 8-decimal format. Default: 50000000 ($0.50)
///
/// Usage:
///   BURVE_LENDER=0x... forge script script/liquidator/CrashOracle.s.sol \
///     --rpc-url http://127.0.0.1:8545 --broadcast -vvv
contract CrashOracle is Script {
    address constant DIAMOND = 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address lenderAddr = vm.envAddress("BURVE_LENDER");
        int256 crashPrice = int256(vm.envOr("CRASH_PRICE", uint256(50000000))); // default $0.50

        BurveLender lender = BurveLender(lenderAddr);
        address[] memory tokens = IBurveMultiSimplex(DIAMOND).getTokens();

        // Log health factors before crash
        uint256 nextId = lender.nextPositionId();
        console2.log("=== BEFORE CRASH ===");
        for (uint256 i = 0; i < nextId; i++) {
            (address borrower,,,,uint256 depValue,) = lender.positions(i);
            if (borrower == address(0) || depValue == 0) continue;

            uint256 colUSD = lender.collateralValueUSD(i);
            uint256 debtUSD = lender.borrowValueUSD(i);
            uint256 hf = lender.healthFactor(i);
            console2.log("Position", i);
            console2.log("  Collateral:", colUSD / 1e18, "USD");
            console2.log("  Debt:      ", debtUSD / 1e18, "USD");
            console2.log("  HF:        ", hf);
        }

        // Crash oracle
        vm.startBroadcast(pk);

        address feed0 = lender.priceFeeds(tokens[0]);
        console2.log("");
        console2.log("=== CRASHING ORACLE ===");
        console2.log("Token:    ", tokens[0]);
        console2.log("Feed:     ", feed0);
        console2.log("New price (8-dec):", uint256(crashPrice));

        MockAggregator(feed0).setPrice(crashPrice);

        vm.stopBroadcast();

        // Log health factors after crash
        console2.log("");
        console2.log("=== AFTER CRASH ===");
        for (uint256 i = 0; i < nextId; i++) {
            (address borrower,,,,uint256 depValue,) = lender.positions(i);
            if (borrower == address(0) || depValue == 0) continue;

            uint256 colUSD = lender.collateralValueUSD(i);
            uint256 debtUSD = lender.borrowValueUSD(i);
            uint256 hf = lender.healthFactor(i);
            bool liquidatable = hf < 1e18;
            console2.log("Position", i, liquidatable ? "[LIQUIDATABLE]" : "[HEALTHY]");
            console2.log("  Collateral:", colUSD / 1e18, "USD");
            console2.log("  Debt:      ", debtUSD / 1e18, "USD");
            console2.log("  HF:        ", hf);
        }
    }
}
