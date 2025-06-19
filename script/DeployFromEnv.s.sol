// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {DiamondCutFacet} from "Commons/Diamond/facets/DiamondCutFacet.sol";
import {InitLib, BurveFacets} from "../src/multi/InitLib.sol";
import {SimplexDiamond as BurveDiamond} from "../src/multi/Diamond.sol";
import {IBurveMultiSimplex} from "../src/multi/interfaces/IBurveMultiSimplex.sol";
import {LockFacet} from "../src/multi/facets/LockFacet.sol";
import {SwapFacet} from "../src/multi/facets/SwapFacet.sol";
import {ValueTokenFacet} from "../src/multi/facets/ValueTokenFacet.sol";
import {VaultType} from "../src/multi/vertex/VaultProxy.sol";
import {IAdjustor} from "../src/integrations/adjustor/IAdjustor.sol";
import {NullAdjustor} from "../src/integrations/adjustor/NullAdjustor.sol";
import {DecimalAdjustor} from "../src/integrations/adjustor/DecimalAdjustor.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

contract DeployFromEnv is Script, Test {
    /* Deployer */
    address deployerAddr;

    uint128 constant INITIAL_VALUE = 1e18;

    /* Diamond */
    address public diamond;
    ValueTokenFacet public valueTokenFacet;
    IBurveMultiSimplex public simplexFacet;
    SwapFacet public swapFacet;
    LockFacet public lockFacet;

    /* Environment Variables */
    address[] public tokens;
    address[] public vaults;
    uint256[] public efactors;

    string public envFile = "script/berachain/usd.json";
    string public deployFile = "script/berachain/deployments/usd.json";

    function run() public {
        deployerAddr = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Read environment configuration
        string memory envJson = vm.readFile(envFile);
        tokens = vm.parseJsonAddressArray(envJson, ".tokens");
        vaults = vm.parseJsonAddressArray(envJson, ".vaults");
        efactors = vm.parseJsonUintArray(envJson, ".efactors");

        vm.startBroadcast(deployerPrivateKey);

        BurveFacets memory facets = InitLib.deployFacets();
        diamond = address(new BurveDiamond(facets, "ValueToken", "BVT"));
        console2.log("Burve deployed at:", diamond);

        valueTokenFacet = ValueTokenFacet(diamond);
        simplexFacet = IBurveMultiSimplex(diamond);
        swapFacet = SwapFacet(diamond);
        lockFacet = LockFacet(diamond);

        IAdjustor nAdj = new DecimalAdjustor();
        simplexFacet.setAdjustor(address(nAdj));

        // set default fee rates
        // 4 bips fee rate 136112946768375385385349842972707284
        // 8% protocol take 27222589353675077077069968594541456916
        simplexFacet.setSimplexFees(
            136112946768375385385349842972707284,
            27222589353675077077069968594541456916
        );

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Add vertices for each token and vault pair
            simplexFacet.addVertex(tokens[i], vaults[i], VaultType.E4626);

            // set efficiency factors
            simplexFacet.setEX128(tokens[i], _toX128(efactors[i]));
        }

        // update specific fee rates

        // Initialize closures from 3 to 2^n - 1 where n is number of tokens
        uint16 maxClosure = uint16((1 << tokens.length) - 1);
        for (uint16 cid = 3; cid <= maxClosure; cid++) {
            _initializeClosure(cid);
        }

        vm.stopBroadcast();

        // Log deployed addresses
        console2.log("Diamond deployed at:", address(diamond));
        for (uint256 i = 0; i < tokens.length; i++) {
            console2.log(
                string.concat("Token", Strings.toString(i), " address:"),
                tokens[i]
            );
            console2.log(
                string.concat("Vault", Strings.toString(i), " address:"),
                vaults[i]
            );
        }

        // Write addresses to JSON file
        string memory json = _generateDeploymentJson();
        vm.writeJson(json, deployFile);
    }

    function _generateDeploymentJson() internal view returns (string memory) {
        string memory json = "{";
        json = string.concat(
            json,
            '"diamond": "',
            vm.toString(address(diamond)),
            '",'
        );

        // Add tokens and vaults arrays
        json = string.concat(json, '"tokens": [');
        for (uint256 i = 0; i < tokens.length; i++) {
            json = string.concat(json, '"', vm.toString(tokens[i]), '"');
            if (i < tokens.length - 1) json = string.concat(json, ",");
        }
        json = string.concat(json, "],");

        json = string.concat(json, '"vaults": [');
        for (uint256 i = 0; i < vaults.length; i++) {
            json = string.concat(json, '"', vm.toString(vaults[i]), '"');
            if (i < vaults.length - 1) json = string.concat(json, ",");
        }
        json = string.concat(json, "]");

        json = string.concat(json, "}");
        return json;
    }

    /// Initialize a zero fee closure with the initial value amount.
    function _initializeClosure(uint16 cid) internal {
        // Mint ourselves enough to fund the initial target of the pool.
        for (uint256 i = 0; i < tokens.length; ++i) {
            if ((1 << i) & cid > 0) {
                deal(tokens[i], deployerAddr, 100e18);
                // IMintableERC20(tokens[i]).mint(address(deployerAddr), 1e33);
                IMintableERC20(tokens[i]).approve(
                    address(diamond),
                    type(uint256).max
                );
            }
        }
        simplexFacet.addClosure(cid, INITIAL_VALUE);
    }

    function _toX128(uint256 amount) internal returns (uint256) {
        return amount << 128;
    }
}

interface IMintableERC20 is IERC20 {
    function mint(address account, uint256 amount) external;
}
