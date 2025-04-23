// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";

contract SimSwap is BaseScript {
    function setUp() public override {
        super.setUp();
    }

    function executeSimSwap(
        uint8 tokenInIndex,
        uint8 tokenOutIndex,
        int256 amountSpecified,
        uint16 closureId
    ) public {
        // Get the private key and sender address
        uint256 privateKey = _getPrivateKey();
        address sender = _getSender();

        // Get token addresses
        address tokenIn = _getTokenByIndex(tokenInIndex);
        address tokenOut = _getTokenByIndex(tokenOutIndex);

        // Log the swap details
        console2.log("Executing SimSwap:");
        console2.log("Token In:", tokenIn);
        console2.log("Token Out:", tokenOut);
        console2.log("Amount Specified:", amountSpecified);
        console2.log("Closure ID:", closureId);

        // Start the broadcast with the private key
        vm.startBroadcast(privateKey);

        // Execute the simSwap
        (
            uint256 inAmount,
            uint256 outAmount,
            uint256 valueExchangedX128
        ) = swapFacet.simSwap(tokenIn, tokenOut, amountSpecified, closureId);

        // Stop the broadcast
        vm.stopBroadcast();

        // Log the result
        console2.log("SimSwap executed successfully");
        console2.log("In Amount:", inAmount);
        console2.log("Out Amount:", outAmount);
        console2.log("Value Exchanged X128:", valueExchangedX128);
    }

    // Helper function to get token out address by index
    function _getTokenOutIndex(uint8 index) internal view returns (address) {
        require(index < tokens.length, "Invalid token out index");
        return address(tokens[index]);
    }
}
