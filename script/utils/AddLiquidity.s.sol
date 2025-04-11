// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;
/*
import "./BaseScript.sol";
import {ClosureId} from "../../src/multi/closure/Id.sol";

contract AddLiquidity is BaseScript {
    function run() external {
        // Load configuration from environment
        address recipient = vm.envOr("RECIPIENT", _getSender());
        uint16 closureId = uint16(vm.envUint("CLOSURE_ID"));
        uint256 amount = vm.envUint("AMOUNT"); // Amount per token

        // Start broadcasting
        vm.startBroadcast(_getPrivateKey());

        // Get LP token for this closure
        BurveMultiLPToken lpToken = _getLPToken(closureId);

        // Get number of vertices from the ViewFacet
        uint8 numTokens = simplexFacet.numVertices();

        console2.log("\nPreparing to add liquidity:");
        console2.log("Closure ID:", closureId);
        console2.log("Amount per token:", amount);
        console2.log("Number of registered tokens:", numTokens);

        // Initialize amounts array
        uint128[] memory amounts = new uint128[](numTokens);
        uint256 tokensProcessed = 0;

        // Process each known token
        address[] memory knownTokens = new address[](4);
        knownTokens[0] = address(usdc);
        knownTokens[1] = address(usdt);
        knownTokens[2] = address(dai);
        knownTokens[3] = address(weth);

        for (uint8 i = 0; i < knownTokens.length; i++) {
            // Get token index from ViewFacet, skip if not registered
            try viewFacet.getTokenIndex(knownTokens[i]) returns (uint8 idx) {
                // Check if token is in closure using ViewFacet
                if (viewFacet.isTokenInClosure(closureId, knownTokens[i])) {
                    _mintAndApprove(knownTokens[i], _getSender(), amount);
                    amounts[idx] = uint128(amount);
                    tokensProcessed++;

                    // Log token details
                    console2.log(
                        string.concat(
                            "Added token ",
                            vm.toString(idx),
                            ": ",
                            vm.toString(knownTokens[i]),
                            " (",
                            MockERC20(knownTokens[i]).symbol(),
                            ")"
                        )
                    );
                }
            } catch {
                // Token not registered, skip it
                continue;
            }
        }

        require(tokensProcessed > 0, "No valid tokens found for this closure");

        // Add liquidity
        uint256 shares = liqFacet.addLiq(recipient, closureId, amounts);

        // Log results
        console2.log("\nLiquidity added successfully:");
        console2.log("Shares minted:", shares);
        console2.log("LP Token:", address(lpToken));
        console2.log("Tokens processed:", tokensProcessed);
        console2.log("Recipient:", recipient);

        vm.stopBroadcast();
    }
}
 */
