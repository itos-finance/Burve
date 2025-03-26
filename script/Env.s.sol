// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BurveFacets, InitLib} from "../src/InitLib.sol";
import {SimplexDiamond} from "../src/multi/Diamond.sol";
import {EdgeFacet} from "../src/multi/facets/EdgeFacet.sol";
import {LiqFacet} from "../src/multi/facets/LiqFacet.sol";
import {SimplexFacet} from "../src/multi/facets/SimplexFacet.sol";
import {SwapFacet} from "../src/multi/facets/SwapFacet.sol";
import {ViewFacet} from "../src/multi/facets/ViewFacet.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ClosureId, newClosureId} from "../src/multi/Closure.sol";
import {VaultType} from "../src/multi/VaultProxy.sol";
import {BurveMultiLPToken} from "../src/multi/LPToken.sol";
import {MockERC4626} from "../test/mocks/MockERC4626.sol";

struct TokenConfig {
    string name;
    string symbol;
    uint8 decimals;
}

struct TokenSet {
    string name;
    TokenConfig[] tokens;
}

contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimalsArg
    ) ERC20(name, symbol) {
        _decimals = decimalsArg;
        _mint(msg.sender, 1000000 * 10 ** decimalsArg);
    }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

contract DeployBurve is Script {
    SimplexDiamond public diamond;
    LiqFacet public liqFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;
    ViewFacet public viewFacet;

    // Token addresses and vaults for current deployment
    address[] public tokens;
    address[] public vaults;
    MockToken[] public mockTokens;
    MockERC4626[] public mockVaults;

    // Mapping to store LP tokens for each closure ID
    mapping(uint16 => BurveMultiLPToken) public lpTokens;
    // Array to store all closure IDs
    uint16[] public closureIds;

    // Used for generating partitions
    bool[] internal used;
    address[] internal currentPartition;

    // File path for deployed addresses
    string constant ADDRESSES_FILE = "deployments.json";

    function getTokenSets() internal pure returns (TokenSet[] memory) {
        // USD Stablecoin Set
        TokenConfig[] memory usdTokens = new TokenConfig[](7);
        usdTokens[0] = TokenConfig("USD Circle", "USDC", 6);
        usdTokens[1] = TokenConfig("Dai Stablecoin", "DAI", 18);
        usdTokens[2] = TokenConfig("Magic Internet Money", "MIM", 18);
        usdTokens[3] = TokenConfig("Aqua USD", "USDA", 6);
        usdTokens[4] = TokenConfig("Sea USD", "USDS", 6);
        usdTokens[5] = TokenConfig("Atlantis USD", "atUSD", 6);
        usdTokens[6] = TokenConfig("Wave USD", "USDW", 6);

        // BTC Set
        TokenConfig[] memory btcTokens = new TokenConfig[](14);
        btcTokens[0] = TokenConfig("Wrapped BTC", "WBTC", 18);
        btcTokens[1] = TokenConfig("Uni BTC", "uniBTC", 18);
        btcTokens[2] = TokenConfig("Lombard BTC", "LBTC", 18);
        btcTokens[3] = TokenConfig("Ape BTC", "apeBTC", 18);
        btcTokens[4] = TokenConfig("Gold BTC", "goldBTC", 18);
        btcTokens[5] = TokenConfig("Hyper BTC", "hyperBTC", 18);
        btcTokens[6] = TokenConfig("Infinite BTC", "infBTC", 18);
        btcTokens[7] = TokenConfig("Berachain BTC", "beraBTC", 18);
        btcTokens[8] = TokenConfig("Good Morning BTC", "gmBTC", 18);
        btcTokens[9] = TokenConfig("Moon BTC", "moonBTC", 18);
        btcTokens[10] = TokenConfig("Lambo BTC", "lamboBTC", 18);
        btcTokens[11] = TokenConfig("Mc BTC", "McBTC", 18);
        btcTokens[12] = TokenConfig("Up BTC", "upBTC", 18);
        btcTokens[13] = TokenConfig("Solar BTC", "solarBTC", 18);

        // ETH Set
        TokenConfig[] memory ethTokens = new TokenConfig[](10);
        ethTokens[0] = TokenConfig("Wrapped Ether", "WETH", 18);
        ethTokens[1] = TokenConfig("Berachain ETH", "beraETH", 18);
        ethTokens[2] = TokenConfig("KelpDAO Restaked ETH", "rsETH", 18);
        ethTokens[3] = TokenConfig("Good Morning ETH", "gmETH", 18);
        ethTokens[4] = TokenConfig("Ape ETH", "apeETH", 18);
        ethTokens[5] = TokenConfig("Moon ETH", "moonETH", 18);
        ethTokens[6] = TokenConfig("Sun ETH", "sunETH", 18);
        ethTokens[7] = TokenConfig("Space ETH", "spaceETH", 18);
        ethTokens[8] = TokenConfig("Shadow ETH", "shadowETH", 18);
        ethTokens[9] = TokenConfig("Warp ETH", "warpETH", 18);

        TokenSet[] memory sets = new TokenSet[](3);
        sets[0] = TokenSet("USD", usdTokens);
        sets[1] = TokenSet("BTC", btcTokens);
        sets[2] = TokenSet("ETH", ethTokens);

        return sets;
    }

    function deployTokenSet(TokenSet memory set) internal returns (string memory) {
        uint256 tokenCount = set.tokens.length;

        // Reset arrays for new deployment
        tokens = new address[](tokenCount);
        vaults = new address[](tokenCount);
        mockTokens = new MockToken[](tokenCount);
        mockVaults = new MockERC4626[](tokenCount);

        console2.log("\n=== Deploying", set.name, "Token Set ===");

        // Deploy tokens and vaults
        for (uint256 i = 0; i < tokenCount; i++) {
            TokenConfig memory config = set.tokens[i];
            mockTokens[i] = new MockToken(
                config.name,
                config.symbol,
                config.decimals
            );
            mockVaults[i] = new MockERC4626(
                mockTokens[i],
                string.concat(config.symbol, " Vault"),
                string.concat("v", config.symbol)
            );
            tokens[i] = address(mockTokens[i]);
            vaults[i] = address(mockVaults[i]);
        }

        // Deploy the diamond and facets
        BurveFacets memory burveFacets = InitLib.deployFacets();
        diamond = new SimplexDiamond(burveFacets);

        // Cast the diamond address to the facet interfaces
        liqFacet = LiqFacet(address(diamond));
        simplexFacet = SimplexFacet(address(diamond));
        swapFacet = SwapFacet(address(diamond));
        viewFacet = ViewFacet(address(diamond));

        // Configure the diamond
        simplexFacet.setName(string.concat(set.name, "-Burve"));
        simplexFacet.setDefaultEdge(101, -46063, 46063, 3000, 200);

        // Add vertices for each token-vault pair
        for (uint256 i = 0; i < tokenCount; i++) {
            simplexFacet.addVertex(tokens[i], vaults[i], VaultType.E4626);
        }

        // Setup edges between all pairs
        _setupEdges();

        // Initialize arrays for partition generation
        used = new bool[](tokenCount);
        currentPartition = new address[](2);

        // Log deployments
        console2.log("\nDeployments for", vm.toLowercase(set.name), "Set:");
        console2.log("Diamond:", address(diamond));
        console2.log("\nToken Addresses:");

        string memory setData = string.concat(set.name, "set");
        vm.serializeAddress(setData, "diamond", address(diamond));

        string memory allTokenData = string.concat(set.name, "tokens");

        string[] memory allTokenJson = new string[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            console2.log(vm.toLowercase(set.tokens[i].symbol), ":", tokens[i]);
            console2.log(
                string.concat(vm.toLowercase(set.tokens[i].symbol), " Vault:"),
                vaults[i]
            );

            string memory tokenData = "tokendata";
            vm.serializeString(tokenData, "symbol", vm.toLowercase(set.tokens[i].symbol));
            vm.serializeAddress(tokenData, "token", tokens[i]);
            allTokenJson[i] = vm.serializeAddress(tokenData, "vault", vaults[i]);
        }

        return vm.serializeString(setData, "tokens", allTokenJson);
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory json;
        string memory finalJson;

        TokenSet[] memory sets = getTokenSets();
        for (uint256 i = 0; i < sets.length; i++) {
            string memory setJson = deployTokenSet(sets[i]);
            finalJson = vm.serializeString(json, vm.toLowercase(sets[i].name), setJson);
        }

        vm.stopBroadcast();

        vm.writeJson(finalJson, ADDRESSES_FILE);
    }

    function _setupEdges() internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                _setupEdge(tokens[i], tokens[j]);
            }
        }
    }

    function _setupEdge(address tokenA, address tokenB) internal {
        EdgeFacet(address(diamond)).setEdge(tokenA, tokenB, 101, -46063, 46063);
    }
}