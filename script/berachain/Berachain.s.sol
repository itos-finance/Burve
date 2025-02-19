// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BaseAdminFacet} from "Commons/Util/Admin.sol";
import {BurveFacets, InitLib} from "../../src/InitLib.sol";
import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {EdgeFacet} from "../../src/multi/facets/EdgeFacet.sol";
import {LiqFacet} from "../../src/multi/facets/LiqFacet.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {ViewFacet} from "../../src/multi/facets/ViewFacet.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {ClosureId, newClosureId} from "../../src/multi/Closure.sol";
import {VaultType} from "../../src/multi/VaultProxy.sol";
import {BurveMultiLPToken} from "../../src/multi/LPToken.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

struct TokenConfig {
    address token;
    address vault;
}

contract BerachainDeploy is Script {
    // Core contracts
    SimplexDiamond public diamond;
    LiqFacet public liqFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;
    ViewFacet public viewFacet;
    EdgeFacet public edgeFacet;

    // Arrays for tokens and vaults
    address[] public tokens;
    address[] public vaults;

    // Mapping to store LP tokens for each closure ID
    mapping(uint16 => BurveMultiLPToken) public lpTokens;
    uint16[] public closureIds;

    // Used for generating partitions
    bool[] internal used;
    address[] internal currentPartition;

    // File paths
    string public constant CONFIG_FILE = "script/berachain/config.json";
    string public constant ADDRESSES_FILE = "script/berachain/deployed.json";

    function run() external {
        // Load configuration
        string memory jsonConfig = vm.readFile(CONFIG_FILE);
        TokenConfig[] memory configs = abi.decode(
            vm.parseJson(jsonConfig),
            (TokenConfig[])
        );

        // Setup tokens and vaults arrays
        tokens = new address[](configs.length);
        vaults = new address[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            tokens[i] = configs[i].token;
            vaults[i] = configs[i].vault;
        }

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the diamond and facets
        BurveFacets memory burveFacets = InitLib.deployFacets();
        diamond = new SimplexDiamond(burveFacets);

        // Cast the diamond address to the facet interfaces
        liqFacet = LiqFacet(address(diamond));
        simplexFacet = SimplexFacet(address(diamond));
        swapFacet = SwapFacet(address(diamond));
        viewFacet = ViewFacet(address(diamond));
        edgeFacet = EdgeFacet(address(diamond));

        // Name the pool and set default edge parameters
        simplexFacet.setName("Burve Berachain Pool");
        simplexFacet.setDefaultEdge(101, -46063, 46063, 3000, 200);

        // Add vertices for each token-vault pair
        for (uint256 i = 0; i < tokens.length; i++) {
            simplexFacet.addVertex(tokens[i], vaults[i], VaultType.E4626);
        }

        // Setup edges between all pairs
        _setupEdges();

        // Initialize arrays for partition generation
        used = new bool[](tokens.length);
        currentPartition = new address[](2); // Start with pairs

        // Setup closures and LP tokens for all possible combinations
        _setupClosuresAndLPTokens();

        // Log deployed addresses
        console2.log("=== Core Contracts ===");
        console2.log("Diamond:", address(diamond));

        console2.log("\n=== Configured Tokens ===");
        for (uint256 i = 0; i < tokens.length; i++) {
            console2.log(
                string.concat(
                    "Token ",
                    vm.toString(i),
                    ": ",
                    vm.toString(tokens[i])
                )
            );
        }

        console2.log("\n=== Configured Vaults ===");
        for (uint256 i = 0; i < vaults.length; i++) {
            console2.log(
                string.concat(
                    "Vault ",
                    vm.toString(i),
                    ": ",
                    vm.toString(vaults[i])
                )
            );
        }

        console2.log("\n=== LP Tokens ===");
        for (uint256 i = 0; i < closureIds.length; i++) {
            uint16 closureId = closureIds[i];
            console2.log(
                string.concat(
                    "LP Token for closure ",
                    vm.toString(closureId),
                    ": ",
                    vm.toString(address(lpTokens[closureId]))
                )
            );
        }

        address safeAddress = vm.envAddress("SAFE_ADDRESS");
        BaseAdminFacet adminFacet = BaseAdminFacet(address(diamond));
        adminFacet.transferOwnership(safeAddress);

        // Save all addresses to JSON file
        _saveAddressesToJson();

        vm.stopBroadcast();
    }

    function _setupEdges() internal {
        // Create edges between all token pairs
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                _setupEdge(tokens[i], tokens[j]);
            }
        }
    }

    function _setupEdge(address tokenA, address tokenB) internal {
        edgeFacet.setEdge(
            tokenA,
            tokenB,
            101, // amplitude
            -46063, // lowTick
            46063 // highTick
        );
    }

    function _setupClosuresAndLPTokens() internal {
        // Generate partitions from size 2 up to the total number of tokens
        for (uint256 size = 2; size <= tokens.length; size++) {
            currentPartition = new address[](size);
            for (uint256 i = 0; i < tokens.length; i++) {
                used[i] = false;
            }
            _generatePartitions(0, 0, size);
        }
    }

    function _generatePartitions(
        uint256 start,
        uint256 currentSize,
        uint256 targetSize
    ) internal {
        if (currentSize == targetSize) {
            // We have a complete partition, create closure and LP token
            uint16 closureId = ClosureId.unwrap(
                viewFacet.getClosureId(currentPartition)
            );

            // Check if we already have this closure
            bool exists = false;
            for (uint256 i = 0; i < closureIds.length; i++) {
                if (closureIds[i] == closureId) {
                    exists = true;
                    break;
                }
            }

            if (!exists) {
                closureIds.push(closureId);
                BurveMultiLPToken lpToken = new BurveMultiLPToken(
                    ClosureId.wrap(closureId),
                    address(diamond)
                );
                lpTokens[closureId] = lpToken;
            }
            return;
        }

        // Try each unused token in this position
        for (uint256 i = start; i < tokens.length; i++) {
            if (!used[i]) {
                used[i] = true;
                currentPartition[currentSize] = tokens[i];
                _generatePartitions(i + 1, currentSize + 1, targetSize);
                used[i] = false;
            }
        }
    }

    function _saveAddressesToJson() internal {
        string memory jsonString = "{\n";

        // Core contracts
        jsonString = string.concat(
            jsonString,
            '    "diamond": "',
            vm.toString(address(diamond)),
            '",\n'
        );

        // Tokens and vaults
        jsonString = string.concat(jsonString, '    "tokens": [\n');
        for (uint256 i = 0; i < tokens.length; i++) {
            jsonString = string.concat(
                jsonString,
                '        {"token": "',
                vm.toString(tokens[i]),
                '", "vault": "',
                vm.toString(vaults[i]),
                '"}',
                i < tokens.length - 1 ? ",\n" : "\n"
            );
        }
        jsonString = string.concat(jsonString, "    ],\n");

        // LP tokens
        jsonString = string.concat(jsonString, '    "lpTokens": {\n');
        for (uint256 i = 0; i < closureIds.length; i++) {
            uint16 closureId = closureIds[i];
            jsonString = string.concat(
                jsonString,
                '        "',
                vm.toString(closureId),
                '": "',
                vm.toString(address(lpTokens[closureId])),
                '"',
                i < closureIds.length - 1 ? ",\n" : "\n"
            );
        }
        jsonString = string.concat(jsonString, "    }\n}");

        // Write to file
        vm.writeFile(ADDRESSES_FILE, jsonString);
        console2.log("\nDeployed addresses saved to:", ADDRESSES_FILE);
    }
}
