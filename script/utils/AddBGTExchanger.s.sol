// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {BGTExchanger} from "../../src/integrations/BGTExchange/BGTExchanger.sol";

contract AddBGTExchanger is BaseScript {
    // Constants
    uint256 constant INITIAL_BGT_SUPPLY = 1_000_000e18;
    uint256 constant DEFAULT_RATE_X128 = 1 << 128; // 1:1 exchange rate

    // Existing diamond address will be loaded from deployment file
    // New contracts to deploy
    MockERC20 public bgtToken;
    BGTExchanger public bgtExchanger;

    function run() public {
        // Get deployer info using base script helpers
        address deployerAddr = _getSender();
        uint256 deployerPrivateKey = _getPrivateKey();

        console2.log("Using deployer address:", deployerAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock BGT token
        bgtToken = new MockERC20("Berachain Governance Token", "BGT", 18);
        console2.log("Deployed BGT token at:", address(bgtToken));

        // Deploy BGT exchanger
        bgtExchanger = new BGTExchanger(address(bgtToken));
        console2.log("Deployed BGT exchanger at:", address(bgtExchanger));

        // Setup BGT token
        bgtToken.mint(deployerAddr, INITIAL_BGT_SUPPLY);
        bgtToken.approve(address(bgtExchanger), INITIAL_BGT_SUPPLY);

        // Fund and configure BGT exchanger
        bgtExchanger.fund(INITIAL_BGT_SUPPLY);
        bgtExchanger.addExchanger(address(diamond));

        // Set exchange rates for all tokens
        uint256 numTokens = _getNumTokens();
        for (uint256 i = 0; i < numTokens; i++) {
            address token = _getTokenByIndex(uint8(i));
            bgtExchanger.setRate(token, DEFAULT_RATE_X128);
            console2.log("Set exchange rate for token:", token);
        }

        // Connect BGT exchanger to the diamond
        simplexFacet.setBGTExchanger(address(bgtExchanger));
        console2.log("Set BGT exchanger on diamond");

        vm.stopBroadcast();

        // Write deployment info to JSON
        string memory json = _generateDeploymentJson();
        vm.writeJson(json, "script/bgt-deployment.json");
    }

    function _generateDeploymentJson() internal view returns (string memory) {
        string memory json = "{";

        json = string.concat(
            json,
            '"bgtToken": "',
            vm.toString(address(bgtToken)),
            '",',
            '"bgtExchanger": "',
            vm.toString(address(bgtExchanger)),
            '"'
        );

        json = string.concat(json, "}");
        return json;
    }
}
