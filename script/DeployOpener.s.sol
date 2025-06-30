// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Opener} from "../src/integrations/opener/Opener.sol";

contract DeployOpener is Script {
    /* Deployer */
    address deployerAddr;

    /* Opener Contract */
    Opener public opener;

    /* Router Addresses */
    address constant BEPOLIA_ROUTER =
        0xADEC0cE4efdC385A44349bD0e55D4b404d5367B4;
    address constant BERACHAIN_ROUTER =
        0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;

    /* Deployment File */
    string public deployFile = "script/berachain/deployments/opener.json";

    function run() public {
        deployerAddr = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Opener contract with Berachain router
        opener = new Opener(BERACHAIN_ROUTER);
        console2.log("Opener deployed at:", address(opener));

        vm.stopBroadcast();

        // Log deployed addresses
        console2.log("Opener deployed at:", address(opener));
        console2.log("Router address:", BERACHAIN_ROUTER);

        // Write addresses to JSON file
        string memory json = _generateDeploymentJson();
        vm.writeJson(json, deployFile);
    }

    function _generateDeploymentJson() internal view returns (string memory) {
        string memory json = "{";
        json = string.concat(
            json,
            '"opener": "',
            vm.toString(address(opener)),
            '",'
        );
        json = string.concat(
            json,
            '"router": "',
            vm.toString(BERACHAIN_ROUTER),
            '"'
        );
        json = string.concat(json, "}");
        return json;
    }
}
