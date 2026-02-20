// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BurveLender} from "../../src/integrations/lender/BurveLender.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @title Liquidate
/// @notice Execute liquidation on an unhealthy position on Anvil.
///
/// Scans all positions, finds liquidatable ones (HF < 1), and liquidates them.
/// Uses empty txData (no swaps) — the removed collateral tokens stay in the lender.
///
/// Env vars:
///   DEPLOYER_PRIVATE_KEY — Anvil account private key (liquidator)
///   BURVE_LENDER — Address of deployed BurveLender
///   POSITION_ID — (optional) Specific position to liquidate. If not set, scans all.
///
/// Usage:
///   BURVE_LENDER=0x... forge script script/liquidator/Liquidate.s.sol \
///     --rpc-url http://127.0.0.1:8545 --broadcast -vvv
contract Liquidate is Script {
    address constant DIAMOND = 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address liquidator = vm.addr(pk);
        address lenderAddr = vm.envAddress("BURVE_LENDER");
        BurveLender lender = BurveLender(lenderAddr);

        address[] memory poolTokens = IBurveMultiSimplex(DIAMOND).getTokens();

        // Check if specific position requested
        uint256 targetId = vm.envOr("POSITION_ID", type(uint256).max);
        uint256 nextId = lender.nextPositionId();

        vm.startBroadcast(pk);

        uint256 liquidated;
        for (uint256 i = 0; i < nextId; i++) {
            if (targetId != type(uint256).max && i != targetId) continue;

            (address borrower,,,,uint256 depValue,) = lender.positions(i);
            if (borrower == address(0) || depValue == 0) continue;

            uint256 hf = lender.healthFactor(i);
            if (hf >= 1e18) {
                console2.log("Position healthy, skipping:", i, hf);
                continue;
            }

            console2.log("Liquidating position", i, "HF:", hf);

            // No swaps needed for Anvil test — empty txData
            bytes[MAX_TOKENS] memory txData;

            // Execute liquidation
            lender.liquidate(i, txData);

            // Check result
            (,,,,uint256 depAfter,) = lender.positions(i);
            console2.log("  Liquidated! Remaining value:", depAfter);

            // Log liquidator balance changes
            for (uint256 j = 0; j < poolTokens.length && j < 3; j++) {
                uint256 bal = IERC20(poolTokens[j]).balanceOf(liquidator);
                console2.log("  Liquidator token", j, "balance:", bal);
            }

            liquidated++;
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== SUMMARY ===");
        console2.log("Positions liquidated:", liquidated);
    }

}
