// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";

contract ClosureFees is BaseScript {
    // 0.3% in X128 format
    uint128 constant FEE_03_PERCENT_X128 =
        1020847100762815390390123822295304634;

    function setUp() public override {
        super.setUp();
    }

    function run() external {
        // console2.log("hello");
        updateAllClosureFees(FEE_03_PERCENT_X128, 1 << 125);
        // updateClosureFees(7, FEE_03_PERCENT_X128, 1 << 125);
    }

    function updateClosureFees(
        uint16 closureId,
        uint128 baseFeeX128,
        uint128 protocolTakeX128
    ) public {
        // Get the private key and sender address
        uint256 privateKey = _getPrivateKey();
        address sender = _getSender();

        // Log the fee update details
        console2.log("Updating Closure Fees:");
        console2.log("Closure ID:", closureId);
        console2.log("Base Fee X128:", baseFeeX128);
        console2.log("Protocol Fee X128:", protocolTakeX128);

        // Start the broadcast with the private key
        vm.startBroadcast(privateKey);

        // Update the closure fees
        simplexFacet.setClosureFees(closureId, baseFeeX128, protocolTakeX128);

        // Stop the broadcast
        vm.stopBroadcast();

        // Log the result
        console2.log("Closure fees updated successfully");
    }

    // Helper function to set 0.3% fees
    function set03PercentFees(uint16 closureId) public {
        updateClosureFees(closureId, FEE_03_PERCENT_X128, 0);
    }

    // Function to update fees for all possible closures
    function updateAllClosureFees(
        uint128 baseFeeX128,
        uint128 protocolTakeX128
    ) public {
        // Get the number of tokens
        address[] memory tokenList = simplexFacet.getTokens();
        uint8 numTokens = uint8(tokenList.length);

        // Calculate the maximum closure ID (2^n - 1)
        uint16 maxClosureId = uint16((1 << numTokens) - 1);

        console2.log("Updating fees for all closures:");
        console2.log("Number of tokens:", numTokens);
        console2.log("Maximum closure ID:", maxClosureId);

        // Iterate through all possible closures (starting from 3)
        for (uint16 closureId = 3; closureId <= maxClosureId; closureId++) {
            // If we can get the closure value, it exists, so update its fees
            console2.log("Updating fees for closure:", closureId);
            updateClosureFees(closureId, baseFeeX128, protocolTakeX128);
        }
    }

    // Helper function to set 0.3% fees for all closures
    function set03PercentFeesForAll() public {
        updateAllClosureFees(FEE_03_PERCENT_X128, 0);
    }
}
