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

contract DeployBurve is Script {
    SimplexDiamond public diamond;
    LiqFacet public liqFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;
    ViewFacet public viewFacet;

    // Token addresses (to be filled in)
    address[] public tokens;
    address[] public vaults;

    // Real tokens
    ERC20 public honey;
    ERC20 public dai;
    ERC20 public mim;
    ERC20 public mead;

    // Mock vaults
    MockERC4626 public mockHoneyVault;
    MockERC4626 public mockDaiVault;
    MockERC4626 public mockMimVault;
    MockERC4626 public mockMeadVault;

    // Mapping to store LP tokens for each closure ID
    mapping(uint16 => BurveMultiLPToken) public lpTokens;
    // Array to store all closure IDs
    uint16[] public closureIds;

    // Used for generating partitions
    bool[] internal used;
    address[] internal currentPartition;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Get token addresses from environment variables
        address honeyAddress = vm.envAddress("HONEY_ADDRESS");
        address daiAddress = vm.envAddress("DAI_ADDRESS");
        address mimAddress = vm.envAddress("MIM_ADDRESS");
        address meadAddress = vm.envAddress("MEAD_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Initialize token interfaces
        honey = ERC20(honeyAddress);
        dai = ERC20(daiAddress);
        mim = ERC20(mimAddress);
        mead = ERC20(meadAddress);

        // Deploy mock vaults
        mockHoneyVault = new MockERC4626(honey, "Honey Vault", "vHONEY");
        mockDaiVault = new MockERC4626(dai, "Dai Vault", "vDAI");
        mockMimVault = new MockERC4626(mim, "MIM Vault", "vMIM");
        mockMeadVault = new MockERC4626(mead, "Mead Vault", "vMEAD");

        // Deploy the diamond and facets
        BurveFacets memory burveFacets = InitLib.deployFacets();
        diamond = new SimplexDiamond(burveFacets);

        // Cast the diamond address to the facet interfaces
        liqFacet = LiqFacet(address(diamond));
        simplexFacet = SimplexFacet(address(diamond));
        swapFacet = SwapFacet(address(diamond));
        viewFacet = ViewFacet(address(diamond));

        /// @dev Name the pool
        simplexFacet.setName("stables");

        simplexFacet.setDefaultEdge(101, -46063, 46063, 3000, 200);

        // Setup tokens and vaults arrays
        tokens = new address[](4);
        vaults = new address[](4);

        // Fill in token addresses with real tokens
        tokens[0] = honeyAddress;
        tokens[1] = daiAddress;
        tokens[2] = mimAddress;
        tokens[3] = meadAddress;

        // Fill in vault addresses with mock vaults
        vaults[0] = address(mockHoneyVault);
        vaults[1] = address(mockDaiVault);
        vaults[2] = address(mockMimVault);
        vaults[3] = address(mockMeadVault);

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
        console2.log("Diamond deployed to:", address(diamond));
        console2.log("\nToken Addresses:");
        console2.log("HONEY:", address(honey));
        console2.log("DAI:", address(dai));
        console2.log("MIM:", address(mim));
        console2.log("MEAD:", address(mead));
        console2.log("\nMock Vault Addresses:");
        console2.log("HONEY Vault:", address(mockHoneyVault));
        console2.log("DAI Vault:", address(mockDaiVault));
        console2.log("MIM Vault:", address(mockMimVault));
        console2.log("MEAD Vault:", address(mockMeadVault));
        console2.log("\nLP Token Addresses:");
        for (uint256 i = 0; i < closureIds.length; i++) {
            uint16 closureId = closureIds[i];
            console2.log(
                string.concat(
                    "LP Token for closure ",
                    vm.toString(closureId),
                    " deployed to: ",
                    vm.toString(address(lpTokens[closureId]))
                )
            );
        }

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
        EdgeFacet(address(diamond)).setEdge(
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

                // Print detailed information about the LP token
                console2.log("----------------------------------------");
                console2.log("New LP Token Created:");
                console2.log("Address:", address(lpToken));
                console2.log("Name:", lpToken.name());
                console2.log("Symbol:", lpToken.symbol());
                console2.log("Tokens in partition:");
                for (uint256 i = 0; i < currentPartition.length; i++) {
                    console2.log("  ", ERC20(currentPartition[i]).symbol());
                }
                console2.log("----------------------------------------");
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
}
