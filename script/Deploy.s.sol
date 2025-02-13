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
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockERC4626} from "../test/mocks/MockERC4626.sol";
import {ClosureId, newClosureId} from "../src/multi/Closure.sol";
import {VaultType} from "../src/multi/VaultProxy.sol";
import {BurveMultiLPToken} from "../src/multi/LPToken.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

contract DeployBurve is Script {
    // Core contracts
    SimplexDiamond public diamond;
    LiqFacet public liqFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;
    ViewFacet public viewFacet;
    EdgeFacet public edgeFacet;

    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockERC20 public dai;
    MockERC20 public weth;

    // Mock vaults
    MockERC4626 public usdcVault;
    MockERC4626 public usdtVault;
    MockERC4626 public daiVault;
    MockERC4626 public wethVault;

    // Arrays for easier iteration
    address[] public tokens;
    address[] public vaults;

    // Mapping to store LP tokens for each closure ID
    mapping(uint16 => BurveMultiLPToken) public lpTokens;
    uint16[] public closureIds;

    // Used for generating partitions
    bool[] internal used;
    address[] internal currentPartition;

    // File path for saving addresses
    string constant ADDRESSES_FILE = "script/anvil.json";

    function run() external {
        // Use Anvil's default account if no deployer key is provided
        uint256 deployerPrivateKey;
        address deployerAddress;

        deployerPrivateKey = vm.envUint("ANVIL_DEFAULT_KEY");
        deployerAddress = vm.envAddress("ANVIL_DEFAULT_ADDR");
        console2.log("Using Anvil's default account for deployment");
        console2.log("Address:", deployerAddress);

        // Fund the deployer account with 100 ETH
        vm.deal(deployerAddress, 100 ether);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy mock vaults
        usdcVault = new MockERC4626(usdc, "USDC Vault", "vUSDC");
        usdtVault = new MockERC4626(usdt, "USDT Vault", "vUSDT");
        daiVault = new MockERC4626(dai, "DAI Vault", "vDAI");
        wethVault = new MockERC4626(weth, "WETH Vault", "vWETH");

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
        simplexFacet.setName("Burve Stable Pool");
        simplexFacet.setDefaultEdge(101, -46063, 46063, 3000, 200);

        // Setup tokens and vaults arrays
        tokens = new address[](4);
        vaults = new address[](4);

        tokens[0] = address(usdc);
        tokens[1] = address(usdt);
        tokens[2] = address(dai);
        tokens[3] = address(weth);

        vaults[0] = address(usdcVault);
        vaults[1] = address(usdtVault);
        vaults[2] = address(daiVault);
        vaults[3] = address(wethVault);

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

        console2.log("\n=== Mock Tokens ===");
        console2.log("USDC:", address(usdc));
        console2.log("USDT:", address(usdt));
        console2.log("DAI:", address(dai));
        console2.log("WETH:", address(weth));

        console2.log("\n=== Mock Vaults ===");
        console2.log("USDC Vault:", address(usdcVault));
        console2.log("USDT Vault:", address(usdtVault));
        console2.log("DAI Vault:", address(daiVault));
        console2.log("WETH Vault:", address(wethVault));

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
        // Generate all possible 2-token partitions
        _generatePartitions(0, 0, 2);

        // Generate all possible 3-token partitions
        currentPartition = new address[](3);
        for (uint256 i = 0; i < tokens.length; i++) {
            used[i] = false;
        }
        _generatePartitions(0, 0, 3);

        // Generate all possible 4-token partitions
        currentPartition = new address[](4);
        for (uint256 i = 0; i < tokens.length; i++) {
            used[i] = false;
        }
        _generatePartitions(0, 0, 4);
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

        // Mock tokens
        jsonString = string.concat(
            jsonString,
            '    "usdc": "',
            vm.toString(address(usdc)),
            '",\n'
        );
        jsonString = string.concat(
            jsonString,
            '    "usdt": "',
            vm.toString(address(usdt)),
            '",\n'
        );
        jsonString = string.concat(
            jsonString,
            '    "dai": "',
            vm.toString(address(dai)),
            '",\n'
        );
        jsonString = string.concat(
            jsonString,
            '    "weth": "',
            vm.toString(address(weth)),
            '",\n'
        );

        // Mock vaults
        jsonString = string.concat(
            jsonString,
            '    "usdcVault": "',
            vm.toString(address(usdcVault)),
            '",\n'
        );
        jsonString = string.concat(
            jsonString,
            '    "usdtVault": "',
            vm.toString(address(usdtVault)),
            '",\n'
        );
        jsonString = string.concat(
            jsonString,
            '    "daiVault": "',
            vm.toString(address(daiVault)),
            '",\n'
        );
        jsonString = string.concat(
            jsonString,
            '    "wethVault": "',
            vm.toString(address(wethVault)),
            '",\n'
        );

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
