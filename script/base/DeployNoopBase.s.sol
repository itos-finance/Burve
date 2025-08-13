// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NoopVault} from "../../src/integrations/pseudo4626/noopVault.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

abstract contract DeployNoopBase is Script {
    /* Deployer */
    address deployerAddr;

    // Configuration hooks - must be implemented by inheriting scripts
    function tokenAddress() internal pure virtual returns (address);
    function vaultName() internal pure virtual returns (string memory);
    function vaultSymbol() internal pure virtual returns (string memory);

    function run() public {
        deployerAddr = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ERC20 token = ERC20(tokenAddress());
        string memory name = vaultName();
        string memory symbol = vaultSymbol();

        NoopVault vault = new NoopVault(token, name, symbol);

        console2.log("NoopVault deployed at:", address(vault));
        console2.log("Token address:", address(token));
        console2.log("Vault name:", name);
        console2.log("Vault symbol:", symbol);

        vm.stopBroadcast();
    }
}
