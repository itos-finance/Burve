// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {MockERC4626} from "../../test/mocks/MockERC4626.sol";
import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {LiqFacet} from "../../src/multi/facets/LiqFacet.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {ViewFacet} from "../../src/multi/facets/ViewFacet.sol";
import {EdgeFacet} from "../../src/multi/facets/EdgeFacet.sol";
import {BurveMultiLPToken} from "../../src/multi/LPToken.sol";
import {TokenRegLib} from "../../src/multi/Token.sol";

abstract contract BaseScript is Script {
    // File path for deployed addresses
    string constant ADDRESSES_FILE = "deployments.json";

    // Deployment type (usd, btc, eth)
    string public deploymentType;

    // Core contracts
    SimplexDiamond public diamond;
    LiqFacet public liqFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;
    ViewFacet public viewFacet;
    EdgeFacet public edgeFacet;

    // Token and vault mappings
    mapping(string => MockERC20) public tokens;
    mapping(string => MockERC4626) public vaults;

    constructor() {
        deploymentType = "usd";
    }

    function setUp() public virtual {
        // Load deployed addresses
        string memory json = vm.readFile(ADDRESSES_FILE);

        // Set up diamond based on deployment type
        string memory diamondPath = string.concat(
            "$.deployments.",
            deploymentType,
            ".diamond"
        );
        address diamondAddr = vm.parseJsonAddress(json, diamondPath);

        diamond = SimplexDiamond(payable(diamondAddr));
        liqFacet = LiqFacet(diamondAddr);
        simplexFacet = SimplexFacet(diamondAddr);
        swapFacet = SwapFacet(diamondAddr);
        viewFacet = ViewFacet(diamondAddr);
        edgeFacet = EdgeFacet(diamondAddr);

        // Load tokens and vaults based on deployment type
        string memory tokensPath = string.concat(
            "$.deployments.",
            deploymentType,
            ".tokens"
        );

        // Parse all tokens and vaults in this deployment
        string[] memory tokenNames = vm.parseJsonKeys(json, tokensPath);
        for (uint i = 0; i < tokenNames.length; i++) {
            string memory tokenName = tokenNames[i];

            // Get token address
            string memory tokenPath = string.concat(
                "$.deployments.",
                deploymentType,
                ".tokens.",
                tokenName,
                ".token"
            );
            address tokenAddr = vm.parseJsonAddress(json, tokenPath);
            tokens[tokenName] = MockERC20(tokenAddr);

            // Get vault address
            string memory vaultPath = string.concat(
                "$.deployments.",
                deploymentType,
                ".tokens.",
                tokenName,
                ".vault"
            );
            address vaultAddr = vm.parseJsonAddress(json, vaultPath);
            vaults[tokenName] = MockERC4626(vaultAddr);
        }
    }

    // Helper function to get the appropriate private key
    function _getPrivateKey() internal view returns (uint256) {
        return vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    // Helper function to get the appropriate sender address
    function _getSender() internal view returns (address) {
        return vm.envAddress("DEPLOYER_PUBLIC_KEY");
    }

    // Helper function to mint tokens and approve spending
    function _mintAndApprove(
        address token,
        address to,
        uint256 amount
    ) internal {
        MockERC20(token).mint(to, amount);
        MockERC20(token).approve(address(diamond), amount);
    }

    // Helper function to mint tokens by name and approve spending
    function _mintAndApproveByName(
        string memory tokenName,
        address to,
        uint256 amount
    ) internal {
        MockERC20 token = tokens[tokenName];
        token.mint(to, amount);
        token.approve(address(diamond), amount);
    }

    // Helper function to get closureId from a list of token addresses
    function _getClosureIdFromTokens(
        address[] memory tokenAddresses
    ) internal view returns (uint16) {
        // Check if all tokens are part of the same closure
        uint16 foundClosureId = 0;

        // Use the default deployment closure ID as a starting point
        uint16 totalClosures = 10; // Assume a reasonable maximum number of closures to check
        uint16 startClosureId = _getDeploymentClosureId();

        // First check the default closure ID for this deployment
        bool allTokensInClosure = true;
        for (uint j = 0; j < tokenAddresses.length; j++) {
            if (
                !viewFacet.isTokenInClosure(startClosureId, tokenAddresses[j])
            ) {
                allTokensInClosure = false;
                break;
            }
        }

        if (allTokensInClosure) {
            return startClosureId;
        }

        // If the default didn't work, try other closures
        for (uint16 i = 1; i <= totalClosures; i++) {
            // Skip the already checked default closure
            if (i == startClosureId) continue;

            allTokensInClosure = true;

            // Check if all provided tokens are in this closure
            for (uint j = 0; j < tokenAddresses.length; j++) {
                if (!viewFacet.isTokenInClosure(i, tokenAddresses[j])) {
                    allTokensInClosure = false;
                    break;
                }
            }

            if (allTokensInClosure) {
                // Found a closure that contains all the tokens
                foundClosureId = i;
                break;
            }
        }

        // If we couldn't find a closure, use the default for the deployment
        if (foundClosureId == 0) {
            console2.log(
                "Warning: No closure found containing all tokens. Using default for deployment."
            );
            foundClosureId = startClosureId;
        }

        return foundClosureId;
    }

    // Helper function to get closureId for a deployment
    function _getDeploymentClosureId() internal view returns (uint16) {
        // Return the closure ID based on the deployment type
        if (keccak256(bytes(deploymentType)) == keccak256(bytes("usd"))) {
            return 1; // Assuming closure ID 1 for USD pool
        } else if (
            keccak256(bytes(deploymentType)) == keccak256(bytes("eth"))
        ) {
            return 2; // Assuming closure ID 2 for ETH pool
        } else if (
            keccak256(bytes(deploymentType)) == keccak256(bytes("btc"))
        ) {
            return 3; // Assuming closure ID 3 for BTC pool
        } else {
            revert("Unknown deployment type");
        }
    }
}
