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

    function getTokenSets() internal pure returns (TokenSet[] memory) {
        // USD Stablecoin Set
        TokenConfig[] memory usdTokens = new TokenConfig[](4);
        usdTokens[0] = TokenConfig("USD Circle", "USDC", 6);
        usdTokens[1] = TokenConfig("Dai Stablecoin", "DAI", 18);
        usdTokens[2] = TokenConfig("Magic Internet Money", "MIM", 18);
        usdTokens[3] = TokenConfig("USD Tether", "USDT", 6);

        // BTC Set
        TokenConfig[] memory btcTokens = new TokenConfig[](3);
        btcTokens[0] = TokenConfig("Wrapped BTC", "WBTC", 18);
        btcTokens[1] = TokenConfig("Uni BTC", "uniBTC", 18);
        btcTokens[2] = TokenConfig("Lombard BTC", "LBTC", 18);

        // ETH Set
        TokenConfig[] memory ethTokens = new TokenConfig[](3);
        ethTokens[0] = TokenConfig("Wrapped Ether", "WETH", 18);
        ethTokens[1] = TokenConfig("Berachain ETH", "beraETH", 18);
        ethTokens[2] = TokenConfig("KelpDAO Restaked ETH", "rsETH", 18);

        TokenSet[] memory sets = new TokenSet[](3);
        sets[0] = TokenSet("USD", usdTokens);
        sets[1] = TokenSet("BTC", btcTokens);
        sets[2] = TokenSet("ETH", ethTokens);

        return sets;
    }

    function deployTokenSet(TokenSet memory set) internal {
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

        // Setup closures and LP tokens
        // TODO: remove we do this in the DeployLpTokens.s.sol
        // _setupClosuresAndLPTokens();

        // Log deployments
        console2.log("\nDeployments for", set.name, "Set:");
        console2.log("Diamond:", address(diamond));
        console2.log("\nToken Addresses:");
        for (uint256 i = 0; i < tokenCount; i++) {
            console2.log(set.tokens[i].symbol, ":", tokens[i]);
            console2.log(
                string.concat(set.tokens[i].symbol, " Vault:"),
                vaults[i]
            );
        }
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TokenSet[] memory sets = getTokenSets();
        for (uint256 i = 0; i < sets.length; i++) {
            deployTokenSet(sets[i]);
        }

        vm.stopBroadcast();
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

    function _setupClosuresAndLPTokens() internal {
        _generatePartitions(0, 0, 2);

        if (tokens.length >= 3) {
            currentPartition = new address[](3);
            for (uint256 i = 0; i < tokens.length; i++) {
                used[i] = false;
            }
            _generatePartitions(0, 0, 3);
        }

        if (tokens.length >= 4) {
            currentPartition = new address[](4);
            for (uint256 i = 0; i < tokens.length; i++) {
                used[i] = false;
            }
            _generatePartitions(0, 0, 4);
        }
    }

    function _generatePartitions(
        uint256 start,
        uint256 currentSize,
        uint256 targetSize
    ) internal {
        if (currentSize == targetSize) {
            uint16 closureId = ClosureId.unwrap(
                viewFacet.getClosureId(currentPartition)
            );

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

        for (uint256 i = start; i < tokens.length; i++) {
            if (!used[i]) {
                used[i] = true;
                currentPartition[currentSize] = tokens[i];
                _generatePartitions(i + 1, currentSize + 1, targetSize);
                used[i] = false;
            }
        }
    }
}
