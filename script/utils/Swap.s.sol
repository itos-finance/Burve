// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";

contract Swap is BaseScript {
    uint128 constant MIN_SQRT_PRICE_X96 = uint128(1 << 96) / 1000;
    uint128 constant MAX_SQRT_PRICE_X96 = uint128(1000 << 96);

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    function run() external {
        // Get configuration from environment or use defaults
        string memory inTokenName = vm.envOr("IN_TOKEN", string("DAI"));
        string memory outTokenName = vm.envOr("OUT_TOKEN", string("USDT"));
        int256 amountSpecified = int256(vm.envOr("AMOUNT", uint256(1000000))); // Default 1 USDC
        address recipient = vm.envOr("RECIPIENT", _getSender());

        // Optional: Allow overriding the deployment type
        if (vm.envExists("DEPLOYMENT_TYPE")) {
            deploymentType = vm.envString("DEPLOYMENT_TYPE");
        }

        // Get token addresses from BaseScript's token mapping
        address inToken = address(tokens[inTokenName]);
        address outToken = address(tokens[outTokenName]);

        require(inToken != address(0), "Input token not found in deployment");
        require(outToken != address(0), "Output token not found in deployment");

        // Determine token ordering and sqrt price limit
        bool zeroForOne = inToken < outToken;
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? uint160(MIN_SQRT_RATIO + 1)
            : uint160(MAX_SQRT_RATIO - 1);

        console2.log("\nExecuting swap:");
        console2.log("Input Token:", inTokenName);
        console2.log("Input Address: ", inToken);
        console2.log("Output Token:", outTokenName);
        console2.log("Output Address: ", outToken);
        console2.log("Amount Specified:", uint256(amountSpecified));
        console2.log("Recipient:", recipient);
        console2.log("Zero For One:", zeroForOne);
        console2.log("sqrtPriceLimitX96", sqrtPriceLimitX96);

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

        console2.log("\nSwap Results:");
        console2.log("Amount In:", amountIn);
        console2.log("Amount Out:", amountOut);

        vm.stopBroadcast();
    }
}
