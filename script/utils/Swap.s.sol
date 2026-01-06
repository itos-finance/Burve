// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";
import {ClosureId} from "../../src/multi/closure/Id.sol";

contract Swap is BaseScript {
    function run() external {
        // Load configuration from environment
        address recipient = vm.envOr("RECIPIENT", _getSender());
        uint16 closureId = uint16(vm.envOr("CLOSURE_ID", uint256(7)));
        address tokenIn = address(tokens[2]);
        address tokenOut = address(tokens[1]);
        uint256 amountIn = vm.envOr("AMOUNT_IN", uint256(1e18));
        uint256 minAmountOut = vm.envOr("MIN_AMOUNT_OUT", uint256(0));

        // Start broadcasting
        // vm.startBroadcast(_getPrivateKey());

        vm.startPrank(address(0xE57Ec670263F20bf40d9d53831a42D0D9eEbBcAe));

        console2.log("\nPreparing to swap:");
        console2.log("Closure ID:", closureId);
        console2.log("Token In:", tokenIn);
        console2.log("Token Out:", tokenOut);
        console2.log("Amount In:", amountIn);
        console2.log("Min Amount Out:", minAmountOut);
        console2.log("Recipient:", recipient);

        recipient = 0xE57Ec670263F20bf40d9d53831a42D0D9eEbBcAe;
        tokenIn = address(0x688e72142674041f8f6Af4c808a4045cA1D6aC82);
        tokenOut = address(0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34);
        amountIn = 131354142;
        minAmountOut = 0;
        closureId = 415;

        // Mint and approve the input token
        // _mintAndApprove(tokenIn, _getSender(), amountIn);

        // Perform the swap
        (uint256 actualIn, uint256 actualOut) = swapFacet.swap(
            recipient,
            tokenIn,
            tokenOut,
            int256(amountIn), // Positive for exact input
            minAmountOut,
            closureId
        );

        // Log the results
        console2.log("\nSwap completed successfully:");
        console2.log("Actual Amount In:", actualIn);
        console2.log("Actual Amount Out:", actualOut);

        vm.stopPrank();

        // vm.stopBroadcast();
    }
}
