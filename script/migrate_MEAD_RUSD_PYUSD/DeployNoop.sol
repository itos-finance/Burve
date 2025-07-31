// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";

import {console2} from "forge-std/console2.sol";

import {NoopVault} from "../../src/integrations/pseudo4626/noopVault.sol";

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract DeployNoop is Script {
    /* Deployer */
    address deployerAddr;

    function run() public {
        deployerAddr = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ERC20 token = ERC20(0xEDB5180661F56077292C92Ab40B1AC57A279a396); // MEAD

        string memory name = "noopMEAD";

        string memory symbol = "noMEAD";

        new NoopVault(token, name, symbol);

        vm.stopBroadcast();
    }
}
