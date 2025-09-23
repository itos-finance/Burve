// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {BRC20} from "../../src/integrations/BRC20.sol";

/// @title DeployBRC20 - Deploy script for BRC20 contract
/// @notice Deploys a BRC20 contract wrapping a specific closureId
contract DeployBRC20 is Script {
    // ========================================
    // DEPLOYMENT PARAMETERS
    // ========================================

    // Pool and closure configuration
    address public constant BURVE_POOL =
        0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089; // Berachain pool
    uint16 public constant CLOSURE_ID = 3; // Closure ID to wrap (3 = USDC/USDT)

    // PoL vault configuration (set to address(0) for no PoL)
    address public constant POL_VAULT = address(0); // PoL vault address
    uint256 public constant FEE_TAKE_X64 = 0; // Fee take in X64 format

    // Token configuration
    string public constant TOKEN_NAME = "Burve BRC20 USD";
    string public constant TOKEN_SYMBOL = "bBRC20USD";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deploying BRC20 contract...");
        console2.log("Deployer:", deployer);
        console2.log("Pool address:", BURVE_POOL);
        console2.log("Closure ID:", CLOSURE_ID);
        console2.log("PoL vault:", POL_VAULT);
        console2.log("Fee take X64:", FEE_TAKE_X64);
        console2.log("Token name:", TOKEN_NAME);
        console2.log("Token symbol:", TOKEN_SYMBOL);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy BRC20 contract
        BRC20 brc20 = new BRC20(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            BURVE_POOL,
            CLOSURE_ID,
            POL_VAULT,
            FEE_TAKE_X64
        );

        vm.stopBroadcast();

        console2.log("BRC20 deployed at:", address(brc20));
        console2.log("BRC20 name:", brc20.name());
        console2.log("BRC20 symbol:", brc20.symbol());
        console2.log("BRC20 pool:", address(brc20.pool()));
        console2.log("BRC20 closureId:", brc20.closureId());
        console2.log("BRC20 polVault:", brc20.polVault());
        console2.log("BRC20 feeTakeX64:", brc20.feeTakeX64());
        console2.log("BRC20 totalShares:", brc20.totalShares());
        console2.log("BRC20 totalValue:", brc20.totalValue());
        console2.log("BRC20 totalSupply:", brc20.totalSupply());
        console2.log("Deployment completed successfully!");
    }
}
