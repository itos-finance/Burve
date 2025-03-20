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

    // Helper function to get LP token for a closure
    function _getLPToken(
        uint16 closureId
    ) internal returns (BurveMultiLPToken) {
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(tokens["token0"]);
        tokenAddresses[1] = address(tokens["token1"]);
        return
            new BurveMultiLPToken(
                viewFacet.getClosureId(tokenAddresses),
                address(diamond)
            );
    }
}
