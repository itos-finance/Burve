// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {ViewFacet} from "../src/multi/facets/ViewFacet.sol";
import {BurveMultiLPToken} from "../src/multi/LPToken.sol";
import {ClosureId} from "../src/multi/Closure.sol";

contract DeployLPTokens is Script {
    using stdJson for string;

    // Struct to hold token data from deployments.json
    struct TokenData {
        string symbol;
        address token;
        address vault;
    }

    struct SetData {
        address diamond;
        TokenData[] tokenData;
    }

    // Mapping to store token sets
    mapping(string => SetData) public sets;
    string[] public setNames;

    // Used for generating partitions
    bool[] internal used;
    address[] internal currentPartition;

    // Store deployed LP tokens
    struct LPDeployment {
        uint16 closureId;
        address lpToken;
        address[] tokens;
    }

    mapping(string setName => LPDeployment[] deployments) public setDeployments;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments.json");
        string memory json = vm.readFile(path);

        // Parse each set
        _parseSet("usd", json, ".usd");
        _parseSet("btc", json, ".btc");
        _parseSet("eth", json, ".eth");
    }

    function _parseSet(
        string memory setName,
        string memory json,
        string memory path
    ) internal {
        setNames.push(setName);

        // Get diamond address
        string memory diamondPath = string.concat(path, ".diamond");
        sets[setName].diamond = json.readAddress(diamondPath);

        // Get tokens data
        string memory tokensPath = string.concat(path, ".tokens");
        bytes memory tokensData = vm.parseJson(json, tokensPath);
        sets[setName].tokenData = abi.decode(tokensData, (TokenData[]));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Log tokens in each set
        for (uint i = 0; i < setNames.length; i++) {
            string memory setName = setNames[i];
            SetData storage set = sets[setName];

            console2.log("\nTokens in", setName, "set:");
            console2.log("Diamond:", set.diamond);
            for (uint j = 0; j < set.tokenData.length; j++) {
                TokenData memory tokenData = set.tokenData[j];
                console2.log(
                    string.concat(
                        "  ",
                        tokenData.symbol,
                        ": token=",
                        vm.toString(tokenData.token),
                        ", vault=",
                        vm.toString(tokenData.vault)
                    )
                );
            }
        }

        // Deploy LP tokens for each set
        for (uint i = 0; i < setNames.length; i++) {
            string memory setName = setNames[i];
            SetData storage set = sets[setName];

            console2.log("\nDeploying LP tokens for", setName, "set");
            console2.log("Diamond:", set.diamond);

            // Setup arrays for combinations
            uint256 numTokens = set.tokenData.length;
            used = new bool[](numTokens);

            // Deploy LP tokens for all combinations of 2 or more tokens
            for (uint256 size = 2; size <= numTokens; size++) {
                currentPartition = new address[](size);
                for (uint256 j = 0; j < numTokens; j++) used[j] = false;
                _generatePartitions(setName, 0, 0, size);
            }
        }

        // Write deployments to file
        string memory outputJson = _generateDeploymentsJson();
        vm.writeFile("lp-deployments.json", outputJson);

        vm.stopBroadcast();
    }

    function _generatePartitions(
        string memory setName,
        uint256 start,
        uint256 currentSize,
        uint256 targetSize
    ) internal {
        if (currentSize == targetSize) {
            ViewFacet viewFacet = ViewFacet(sets[setName].diamond);
            uint16 closureId = ClosureId.unwrap(
                viewFacet.getClosureId(currentPartition)
            );

            // Deploy LP token
            BurveMultiLPToken lpToken = new BurveMultiLPToken(
                ClosureId.wrap(closureId),
                sets[setName].diamond
            );

            // Store deployment info
            address[] memory tokensCopy = new address[](
                currentPartition.length
            );
            for (uint i = 0; i < currentPartition.length; i++) {
                tokensCopy[i] = currentPartition[i];
            }
            setDeployments[setName].push(
                LPDeployment(closureId, address(lpToken), tokensCopy)
            );

            console2.log("Deployed LP token for closure", closureId);
            console2.log("LP token address:", address(lpToken));
            return;
        }

        SetData storage set = sets[setName];
        for (uint256 i = start; i < set.tokenData.length; i++) {
            if (!used[i]) {
                used[i] = true;
                currentPartition[currentSize] = set.tokenData[i].token;
                _generatePartitions(
                    setName,
                    i + 1,
                    currentSize + 1,
                    targetSize
                );
                used[i] = false;
            }
        }
    }

    function _generateDeploymentsJson() internal returns (string memory) {
        string memory json;
        string memory finalJson;

        for (uint i = 0; i < setNames.length; ++i) {
            string memory setName = setNames[i];
            LPDeployment[] memory deployments = setDeployments[setName];

            string[] memory deploymentsJson = new string[](deployments.length);
            for (uint j = 0; j < deployments.length; ++j) {
                LPDeployment memory deployment = deployments[j];

                string[] memory tokensJson = new string[](
                    deployment.tokens.length
                );
                for (uint k = 0; k < deployment.tokens.length; ++k) {
                    string memory tokenData = "tokendata";
                    vm.serializeAddress(
                        tokenData,
                        "address",
                        deployment.tokens[k]
                    );
                    tokensJson[k] = vm.serializeString(
                        tokenData,
                        "symbol",
                        vm.toLowercase(IERC20(deployment.tokens[k]).symbol())
                    );
                }

                string memory deploymentData = "deploymentData";
                vm.serializeUint(
                    deploymentData,
                    "closureId",
                    deployment.closureId
                );
                vm.serializeAddress(
                    deploymentData,
                    "lpToken",
                    deployment.lpToken
                );
                deploymentsJson[j] = vm.serializeString(
                    deploymentData,
                    "tokens",
                    tokensJson
                );
            }

            finalJson = vm.serializeString(json, setName, deploymentsJson);
        }

        return finalJson;
    }
}
