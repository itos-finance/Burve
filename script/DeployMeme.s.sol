// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";

import {console2} from "forge-std/console2.sol";

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract CubbieBera is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}
}

contract DeployMeme is Script {
    /* Deployer */
    address deployerAddr;

    function run() public {
        deployerAddr = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployment = address(new CubbieBera("CubbieBera", "CUBS"));
        console2.log("deployment", deployment);

        vm.stopBroadcast();
    }
}
