// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {DealScript} from "./ScriptBase.sol";
import {Lender} from "../../src/integrations/lender/Lender.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {PositionHelper} from "./PositionHelper.sol";

/// @title SetupPositions
/// @notice On an Anvil fork, create lending pools + borrower positions on Lender.
///
/// Env vars:
///   DEPLOYER_PRIVATE_KEY — Anvil account private key
///   BURVE_LENDER — Address of deployed Lender (from DeployLenderAnvil)
///
/// Usage:
///   BURVE_LENDER=0x... forge script script/liquidator/SetupPositions.s.sol \
///     --rpc-url http://127.0.0.1:8545 --broadcast -vvv
contract SetupPositions is DealScript {
    address constant DIAMOND = 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address lenderAddr = vm.envAddress("BURVE_LENDER");
        Lender lender = Lender(lenderAddr);

        address[] memory tokens = IBurveMultiSimplex(DIAMOND).getTokens();
        uint16 closureId = 3;

        vm.startBroadcast(pk);

        // Deploy PositionHelper
        PositionHelper helper = new PositionHelper(DIAMOND);
        console2.log("PositionHelper:", address(helper));

        // ---- Step 1: Seed lending pools ----
        console2.log("=== Seeding Lending Pools ===");
        uint256 lpAmount = 50_000e18;
        for (uint256 i = 0; i < tokens.length && i < 3; i++) {
            _deal(tokens[i], deployer, lpAmount);
            IERC20(tokens[i]).approve(lenderAddr, lpAmount);
            lender.depositLiquidity(tokens[i], lpAmount);
            console2.log("  Pool seeded:", i);
        }

        uint128 depositValue = 200e18;

        // ---- Step 2: Create healthy position ----
        console2.log("=== Healthy Position (10% LTV) ===");
        for (uint256 i = 0; i < tokens.length; i++) {
            if ((1 << i) & closureId > 0) {
                _deal(tokens[i], address(helper), uint256(depositValue) * 2);
            }
        }
        uint256 posId0 = helper.createPosition(lenderAddr, closureId, depositValue, tokens[0], 10);
        console2.log("  Position ID:", posId0);
        _logPosition(lender, posId0);

        // ---- Step 3: Near-max-LTV position ----
        console2.log("=== Near-Max Position (75% LTV) ===");
        for (uint256 i = 0; i < tokens.length; i++) {
            if ((1 << i) & closureId > 0) {
                _deal(tokens[i], address(helper), uint256(depositValue) * 2);
            }
        }
        uint256 posId1 = helper.createPosition(lenderAddr, closureId, depositValue, tokens[0], 75);
        console2.log("  Position ID:", posId1);
        _logPosition(lender, posId1);

        vm.stopBroadcast();

        console2.log("");
        console2.log("Healthy position:", posId0);
        console2.log("Liquidation target:", posId1);
    }

    function _logPosition(Lender lender, uint256 positionId) internal view {
        uint256 colUSD = lender.collateralValueUSD(positionId);
        uint256 debtUSD = lender.borrowValueUSD(positionId);
        uint256 hf = lender.healthFactor(positionId);
        console2.log("  Collateral USD:", colUSD / 1e18);
        console2.log("  Debt USD:      ", debtUSD / 1e18);
        console2.log("  Health Factor: ", hf);
    }
}
