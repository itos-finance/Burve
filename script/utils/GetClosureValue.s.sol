// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";

contract GetClosureValue is BaseScript {
    function run() external view {
        // Load closure ID from environment variable
        uint16 closureId = uint16(vm.envOr("CLOSURE_ID", uint256(3)));

        require(
            closureId > 0,
            "CLOSURE_ID must be provided and greater than 0"
        );

        console2.log("\n=== Getting Closure Value ===");
        console2.log("Closure ID:", closureId);

        // Call getClosureValue function
        (
            uint8 n,
            uint256 targetX128,
            uint256[MAX_TOKENS] memory balances,
            uint256 valueStaked,
            uint256 bgtValueStaked
        ) = simplexFacet.getClosureValue(closureId);

        // Display results
        console2.log("\n--- Closure Value Information ---");
        console2.log("Number of tokens (n):", n);
        console2.log("Target X128:", targetX128);
        console2.log("Value staked:", valueStaked);
        console2.log("BGT value staked:", bgtValueStaked);

        console2.log("\n--- Token Balances ---");
        for (uint8 i = 0; i < MAX_TOKENS; i++) {
            if (balances[i] > 0) {
                console2.log("Token", i, "balance:", balances[i]);
            }
        }

        console2.log("\n=== Closure Value Retrieved Successfully ===");
    }
}
