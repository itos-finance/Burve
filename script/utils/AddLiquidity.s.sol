// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";

contract AddLiquidity is BaseScript {
    function run() external {
        // Get configuration
        uint256 amount = vm.envOr("AMOUNT", uint256(100_000_000)); // Default 1 USDC/USDT/DAI
        address recipient = vm.envOr("RECIPIENT", _getSender());

        // Start broadcasting
        vm.startBroadcast(_getPrivateKey());

        // Get number of tokens in registry
        uint8 numTokens = simplexFacet.numVertices();

        // Create amounts array (all zeros by default)
        uint128[] memory amounts = new uint128[](numTokens);

        // Set up USD stablecoin amounts
        // Get token indexes from the registry
        uint8 usdcIndex = viewFacet.getTokenIndex(address(tokens["USDC"]));
        uint8 usdtIndex = viewFacet.getTokenIndex(address(tokens["USDT"]));
        uint8 daiIndex = viewFacet.getTokenIndex(address(tokens["DAI"]));
        uint8 mimIndex = viewFacet.getTokenIndex(address(tokens["MIM"]));

        console2.log("usdcIndex", usdcIndex);
        console2.log("usdtIndex", usdtIndex);
        console2.log("daiIndex", daiIndex);
        console2.log("mimIndex", mimIndex);

        // Set amounts for each token
        amounts[usdcIndex] = uint128(
            amount * 10 ** uint256(tokens["USDC"].decimals())
        );
        amounts[usdtIndex] = uint128(
            amount * 10 ** uint256(tokens["USDT"].decimals())
        );
        amounts[daiIndex] = uint128(
            amount * 10 ** uint256(tokens["DAI"].decimals())
        );
        amounts[mimIndex] = uint128(
            amount * 10 ** uint256(tokens["MIM"].decimals())
        );

        // Mint and approve tokens
        _mintAndApproveByName(
            "USDC",
            _getSender(),
            amount * 10 ** uint256(tokens["USDC"].decimals())
        );
        _mintAndApproveByName(
            "USDT",
            _getSender(),
            amount * 10 ** uint256(tokens["USDT"].decimals())
        );
        _mintAndApproveByName(
            "DAI",
            _getSender(),
            amount * 10 ** uint256(tokens["DAI"].decimals())
        );
        _mintAndApproveByName(
            "MIM",
            _getSender(),
            amount * 10 ** uint256(tokens["MIM"].decimals())
        );

        // Get closure ID for USD pool (hardcoded to 1 for USD pool)
        uint16 closureId = 15;

        console2.log("\nAdding liquidity to USD pool:");
        console2.log("Amount per token:", amount);
        console2.log("Closure ID:", closureId);

        // Add liquidity
        uint256 shares = liqFacet.addLiq(recipient, closureId, amounts);

        console2.log("\nLiquidity added successfully!");
        console2.log("Shares received:", shares);

        vm.stopBroadcast();
    }
}
