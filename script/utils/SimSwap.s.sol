// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";

contract SimSwap is BaseScript {
    uint128 constant MIN_SQRT_PRICE_X96 = uint128(1 << 96) / 1000;
    uint128 constant MAX_SQRT_PRICE_X96 = uint128(1000 << 96);

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    function run() external {
        // Get configuration from environment or use defaults
        string memory inTokenName = vm.envOr("IN_TOKEN", string("USDT"));
        string memory outTokenName = vm.envOr("OUT_TOKEN", string("MIM"));
        int256 amountSpecified = int256(vm.envOr("AMOUNT", uint256(1000000))); // Default 1 USDC

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

        console2.log("\nSimulating swap:");
        console2.log("Input Token:", inTokenName);
        console2.log("Input Address: ", inToken);
        console2.log("Output Token:", outTokenName);
        console2.log("Output Address: ", outToken);
        console2.log("Amount Specified:", uint256(amountSpecified));
        console2.log("Zero For One:", zeroForOne);
        console2.log("sqrtPriceLimitX96", sqrtPriceLimitX96);

        // Perform simulated swap
        (
            uint256 amountIn,
            uint256 amountOut,
            uint160 finalSqrtPriceX96
        ) = swapFacet.simSwap(inToken, outToken, 1_000_000, sqrtPriceLimitX96);

        console2.log("\nSimulated Swap Results:");
        console2.log("Amount In:", amountIn);
        console2.log("Amount Out:", amountOut);
        console2.log("Final Sqrt Price X96:", finalSqrtPriceX96);

        // Get and display current price
        uint160 currentSqrtPriceX96 = swapFacet.getSqrtPrice(inToken, outToken);
        console2.log("\nPricing Information:");
        console2.log("Current Sqrt Price X96:", currentSqrtPriceX96);

        // Calculate and display price impact
        if (currentSqrtPriceX96 > 0) {
            uint256 priceImpactBps;
            if (finalSqrtPriceX96 > currentSqrtPriceX96) {
                priceImpactBps =
                    ((finalSqrtPriceX96 - currentSqrtPriceX96) * 10000) /
                    currentSqrtPriceX96;
            } else {
                priceImpactBps =
                    ((currentSqrtPriceX96 - finalSqrtPriceX96) * 10000) /
                    currentSqrtPriceX96;
            }
            console2.log("Estimated Price Impact (bps):", priceImpactBps);
        }
    }
}

// Interface for the SwapFacet to call its functions
interface SwapFacetInterface {
    function simSwap(
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )
        external
        view
        returns (
            uint256 inAmount,
            uint256 outAmount,
            uint160 finalSqrtPriceX96
        );

    function getSqrtPrice(
        address inToken,
        address outToken
    ) external view returns (uint160 sqrtPriceX96);
}
