// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BurveLender} from "../../src/integrations/lender/BurveLender.sol";
import {BurveLooper} from "../../src/integrations/looper/BurveLooper.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {MockAggregator} from "./MockAggregator.sol";

/// @title DeployLenderAnvil
/// @notice Deploy BurveLender + mock oracles on an Anvil fork of Berachain.
///         Uses the live diamond at 0xa1beD...089 and deploys mock Chainlink
///         price feeds for all pool tokens (all set to $1.00 initially).
///
/// Usage:
///   forge script script/liquidator/DeployLenderAnvil.s.sol \
///     --rpc-url http://127.0.0.1:8545 --broadcast -vvv
///
/// After running, note the addresses printed — paste them into subsequent scripts.
contract DeployLenderAnvil is Script {
    address constant DIAMOND = 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;
    // Mock router — we don't need real swaps for testing, liquidation will use mock
    address constant MOCK_ROUTER = address(0xDEAD);

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(pk);

        // Deploy BurveLender
        BurveLender lender = new BurveLender(MOCK_ROUTER);
        console2.log("BurveLender:", address(lender));

        // Deploy BurveLooper
        BurveLooper looper = new BurveLooper(address(lender));
        console2.log("BurveLooper:", address(looper));

        // Get pool tokens from live diamond
        address[] memory tokens = IBurveMultiSimplex(DIAMOND).getTokens();
        console2.log("Pool has", tokens.length, "tokens");

        // Deploy mock oracles for each token, all at $1.00
        for (uint256 i = 0; i < tokens.length; i++) {
            MockAggregator oracle = new MockAggregator(1e8, 8); // $1.00
            lender.setPriceFeed(tokens[i], address(oracle), 18); // 18-dec nominal
            console2.log("  Token", i, tokens[i]);
            console2.log("  Oracle", i, address(oracle));
        }

        vm.stopBroadcast();

        // Summary
        console2.log("");
        console2.log("=== DEPLOYMENT SUMMARY ===");
        console2.log("Diamond:     ", DIAMOND);
        console2.log("BurveLender: ", address(lender));
        console2.log("BurveLooper: ", address(looper));
        console2.log("All oracles set to $1.00 (1e8)");
    }
}
