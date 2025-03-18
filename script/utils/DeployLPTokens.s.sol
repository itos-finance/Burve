// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";
import {ClosureId} from "../../src/multi/Closure.sol";
import {BurveMultiLPToken} from "../../src/multi/LPToken.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";

contract DeployLPTokens is BaseScript {
    using stdJson for string;

    // Used for generating partitions
    bool[] internal used;
    address[] internal currentPartition;
    string[] internal currentPartitionSymbols;

    // Store deployed LP tokens and closure IDs with their tokens
    mapping(uint16 => BurveMultiLPToken) public lpTokens;
    mapping(uint16 => address[]) public closureTokens;
    mapping(uint16 => string[]) public closureSymbols;
    uint16[] public closureIds;

    function run() external {
        // Start with USD pool
        deploymentType = "usd";

        // Get all token addresses for the USD pool
        address[] memory poolTokens = new address[](4);
        string[] memory poolSymbols = new string[](4);

        poolTokens[0] = address(tokens["USDC"]);
        poolTokens[1] = address(tokens["DAI"]);
        poolTokens[2] = address(tokens["MIM"]);
        poolTokens[3] = address(tokens["USDT"]);

        poolSymbols[0] = "USDC";
        poolSymbols[1] = "DAI";
        poolSymbols[2] = "MIM";
        poolSymbols[3] = "USDT";

        console2.log("\nGenerating partitions for USD pool tokens:");
        for (uint i = 0; i < poolTokens.length; i++) {
            console2.log(
                string.concat(poolSymbols[i], ": ", vm.toString(poolTokens[i]))
            );
        }

        // Initialize arrays for partition generation
        used = new bool[](poolTokens.length);

        vm.startBroadcast(_getPrivateKey());

        // Generate and deploy LP tokens for 2-token partitions
        console2.log("\nDeploying LP tokens for 2-token partitions:");
        currentPartition = new address[](2);
        currentPartitionSymbols = new string[](2);
        _generatePartitions(poolTokens, poolSymbols, 0, 0, 2);

        // Generate and deploy LP tokens for 3-token partitions
        console2.log("\nDeploying LP tokens for 3-token partitions:");
        currentPartition = new address[](3);
        currentPartitionSymbols = new string[](3);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            used[i] = false;
        }
        _generatePartitions(poolTokens, poolSymbols, 0, 0, 3);

        // Generate and deploy LP tokens for 4-token partitions
        console2.log("\nDeploying LP tokens for 4-token partitions:");
        currentPartition = new address[](4);
        currentPartitionSymbols = new string[](4);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            used[i] = false;
        }
        _generatePartitions(poolTokens, poolSymbols, 0, 0, 4);

        vm.stopBroadcast();

        // Print summary and save deployment info
        string memory output = "{\n";
        output = string.concat(output, '  "lpTokens": {\n');

        console2.log("\nDeployment Summary:");
        console2.log("Total LP tokens deployed:", closureIds.length);

        for (uint256 i = 0; i < closureIds.length; i++) {
            uint16 closureId = closureIds[i];
            address lpTokenAddr = address(lpTokens[closureId]);
            address[] memory tokens = closureTokens[closureId];
            string[] memory symbols = closureSymbols[closureId];

            // Add to JSON output
            output = string.concat(
                output,
                '    "',
                vm.toString(closureId),
                '": {\n',
                '      "address": "',
                vm.toString(lpTokenAddr),
                '",\n',
                '      "tokens": ['
            );

            // Add token details for this closure
            for (uint256 j = 0; j < tokens.length; j++) {
                output = string.concat(
                    output,
                    '\n        {"symbol": "',
                    symbols[j],
                    '", "address": "',
                    vm.toString(tokens[j]),
                    '"}'
                );
                if (j < tokens.length - 1) {
                    output = string.concat(output, ",");
                }
            }
            output = string.concat(output, "\n      ]");
            output = string.concat(output, "\n    }");

            if (i < closureIds.length - 1) {
                output = string.concat(output, ",");
            }
            output = string.concat(output, "\n");

            // Log to console
            console2.log(
                string.concat(
                    "Closure ID ",
                    vm.toString(closureId),
                    " (",
                    vm.toString(lpTokenAddr),
                    "):"
                )
            );
            for (uint256 j = 0; j < tokens.length; j++) {
                console2.log(
                    string.concat(
                        "  - ",
                        symbols[j],
                        ": ",
                        vm.toString(tokens[j])
                    )
                );
            }
        }

        output = string.concat(output, "  }\n}");

        // Write deployment info to a new file
        vm.writeFile("lp-deployments.json", output);
        console2.log("\nDeployment info written to lp-deployments.json");
    }

    function _generatePartitions(
        address[] memory poolTokens,
        string[] memory poolSymbols,
        uint256 start,
        uint256 currentSize,
        uint256 targetSize
    ) internal {
        if (currentSize == targetSize) {
            // Get closure ID for current partition
            uint16 closureId = ClosureId.unwrap(
                viewFacet.getClosureId(currentPartition)
            );

            // Check if we already deployed an LP token for this closure
            bool exists = false;
            for (uint256 i = 0; i < closureIds.length; i++) {
                if (closureIds[i] == closureId) {
                    exists = true;
                    break;
                }
            }

            if (!exists) {
                // Deploy new LP token
                BurveMultiLPToken lpToken = new BurveMultiLPToken(
                    ClosureId.wrap(closureId),
                    address(diamond)
                );
                lpTokens[closureId] = lpToken;
                closureIds.push(closureId);

                // Store tokens and symbols for this closure
                address[] memory tokens = new address[](
                    currentPartition.length
                );
                string[] memory symbols = new string[](currentPartition.length);
                for (uint256 i = 0; i < currentPartition.length; i++) {
                    tokens[i] = currentPartition[i];
                    symbols[i] = currentPartitionSymbols[i];
                }
                closureTokens[closureId] = tokens;
                closureSymbols[closureId] = symbols;

                // Log the deployment
                console2.log(
                    string.concat(
                        "Deployed LP token for closure ",
                        vm.toString(closureId),
                        ": ",
                        vm.toString(address(lpToken))
                    )
                );

                // Log the tokens in this partition
                console2.log("Tokens in partition:");
                for (uint256 i = 0; i < currentPartition.length; i++) {
                    console2.log(
                        string.concat(
                            "  - ",
                            currentPartitionSymbols[i],
                            ": ",
                            vm.toString(currentPartition[i])
                        )
                    );
                }
            }
            return;
        }

        for (uint256 i = start; i < poolTokens.length; i++) {
            if (!used[i]) {
                used[i] = true;
                currentPartition[currentSize] = poolTokens[i];
                currentPartitionSymbols[currentSize] = poolSymbols[i];
                _generatePartitions(
                    poolTokens,
                    poolSymbols,
                    i + 1,
                    currentSize + 1,
                    targetSize
                );
                used[i] = false;
            }
        }
    }
}
