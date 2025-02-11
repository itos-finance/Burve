// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";

contract Swap is BaseScript {
    uint128 constant MIN_SQRT_PRICE_X96 = uint128(1 << 96) / 1000;
    uint128 constant MAX_SQRT_PRICE_X96 = uint128(1000 << 96);

    function run() external {
        // Load configuration from environment
        address recipient = vm.envOr("RECIPIENT", _getSender());
        address inToken = vm.envAddress("IN_TOKEN");
        address outToken = vm.envAddress("OUT_TOKEN");
        int256 amountSpecified = int256(vm.envUint("AMOUNT")); // Positive for exact input, negative for exact output
        uint160 sqrtPriceLimitX96 = uint160(
            vm.envOr("SQRT_PRICE_LIMIT", MIN_SQRT_PRICE_X96 + 1)
        );

        // Start broadcasting
        vm.startBroadcast(_getPrivateKey());

        // If amount is positive (exact input), mint and approve input tokens
        if (amountSpecified > 0) {
            _mintAndApprove(inToken, _getSender(), uint256(amountSpecified));
        }

        // Perform swap
        (uint256 amountIn, uint256 amountOut) = swapFacet.swap(
            recipient,
            inToken,
            outToken,
            amountSpecified,
            sqrtPriceLimitX96
        );

        console2.log("Swap executed:");
        console2.log("Input Token:", inToken);
        console2.log("Output Token:", outToken);
        console2.log("Amount In:", amountIn);
        console2.log("Amount Out:", amountOut);

        vm.stopBroadcast();
    }
}
