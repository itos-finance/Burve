// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {FeeVaultWrapper} from "../../src/integrations/fee4626/FeeVaultWrapper.sol";

/// @title DeployFeeVaultsBase
/// @notice Deployment script for FeeVaultWrapper contracts on Base blockchain
/// @dev Wraps Aave V3 aTokens with configurable fee-charging wrappers
contract DeployFeeVaultsBase is Script {
    // ============ Constants ============

    /// @notice Aave V3 Pool address on Base
    address constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    /// @notice USDC address on Base (native)
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @notice USDbC address on Base (bridged)
    address constant USDbC = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;

    // ============ State Variables ============

    address public deployerAddr;
    address public feeRecipient;

    FeeVaultWrapper public usdcFeeVault;
    FeeVaultWrapper public usdBcFeeVault;

    string public configFile = "script/base/config/fee-vaults.json";
    string public deployFile = "script/base/deployments/fee-vaults.json";

    // ============ Main Script ============

    function run() public {
        // Get deployer from environment
        deployerAddr = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Read configuration
        string memory configJson = vm.readFile(configFile);
        feeRecipient = vm.parseJsonAddress(configJson, ".feeRecipient");

        // If fee recipient is zero address, use deployer
        if (feeRecipient == address(0)) {
            feeRecipient = deployerAddr;
            console2.log("Using deployer as fee recipient:", deployerAddr);
        }

        console2.log("Deploying Fee Vaults to Base...");
        console2.log("Deployer:", deployerAddr);
        console2.log("Fee Recipient:", feeRecipient);
        console2.log("Aave Pool:", AAVE_POOL);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy USDC Fee Vault
        address usdcAToken = _getAaveAToken(USDC);
        console2.log("USDC aToken:", usdcAToken);

        usdcFeeVault = new FeeVaultWrapper(
            IERC4626(usdcAToken),
            "Fee USDC Vault",
            "fUSDC",
            feeRecipient
        );
        console2.log("USDC Fee Vault deployed at:", address(usdcFeeVault));

        // Deploy USDbC Fee Vault
        address usdBcAToken = _getAaveAToken(USDbC);
        console2.log("USDbC aToken:", usdBcAToken);

        usdBcFeeVault = new FeeVaultWrapper(
            IERC4626(usdBcAToken),
            "Fee USDbC Vault",
            "fUSDbC",
            feeRecipient
        );
        console2.log("USDbC Fee Vault deployed at:", address(usdBcFeeVault));

        vm.stopBroadcast();

        // Write deployment info
        _writeDeploymentJson();

        console2.log("\n=== Deployment Complete ===");
        console2.log("USDC Fee Vault:", address(usdcFeeVault));
        console2.log("USDbC Fee Vault:", address(usdBcFeeVault));
        console2.log("Deployment info written to:", deployFile);
    }

    // ============ Internal Helpers ============

    /// @notice Get Aave aToken address for a given asset
    /// @param asset The underlying asset address
    /// @return aToken The corresponding aToken address
    function _getAaveAToken(address asset) internal view returns (address aToken) {
        // Call getReserveData on Aave Pool
        // Aave Pool interface (simplified for this call)
        bytes memory callData = abi.encodeWithSignature("getReserveData(address)", asset);
        (bool success, bytes memory returnData) = AAVE_POOL.staticcall(callData);

        require(success, "Failed to get Aave reserve data");

        // Decode ReserveData struct (we only need aTokenAddress at offset 64)
        // struct ReserveData {
        //   ReserveConfigurationMap configuration; (256 bits)
        //   uint128 liquidityIndex; (128 bits)
        //   uint128 currentLiquidityRate; (128 bits)
        //   uint128 variableBorrowIndex; (128 bits)
        //   uint128 currentVariableBorrowRate; (128 bits)
        //   uint128 currentStableBorrowRate; (128 bits)
        //   uint40 lastUpdateTimestamp; (40 bits)
        //   uint16 id; (16 bits)
        //   address aTokenAddress; <- This is what we want (160 bits)
        //   ...
        // }

        assembly {
            // Skip length prefix (32 bytes) and configuration (32 bytes)
            // Then skip liquidityIndex + rates (32 + 32 + 32 bytes)
            // aTokenAddress starts at offset 160 bytes
            aToken := mload(add(returnData, 160))
        }

        require(aToken != address(0), "Invalid aToken address");
    }

    /// @notice Write deployment information to JSON file
    function _writeDeploymentJson() internal {
        string memory json = "{";

        // Network info
        json = string.concat(json, '"network": "base",');
        json = string.concat(json, '"aavePool": "', vm.toString(AAVE_POOL), '",');
        json = string.concat(json, '"feeRecipient": "', vm.toString(feeRecipient), '",');

        // USDC vault info
        json = string.concat(json, '"usdc": {');
        json = string.concat(json, '"asset": "', vm.toString(USDC), '",');
        json = string.concat(
            json,
            '"aToken": "',
            vm.toString(address(usdcFeeVault.underlyingVault())),
            '",'
        );
        json = string.concat(json, '"feeVault": "', vm.toString(address(usdcFeeVault)), '",');
        json = string.concat(json, '"name": "Fee USDC Vault",');
        json = string.concat(json, '"symbol": "fUSDC"');
        json = string.concat(json, "},");

        // USDbC vault info
        json = string.concat(json, '"usdbc": {');
        json = string.concat(json, '"asset": "', vm.toString(USDbC), '",');
        json = string.concat(
            json,
            '"aToken": "',
            vm.toString(address(usdBcFeeVault.underlyingVault())),
            '",'
        );
        json = string.concat(json, '"feeVault": "', vm.toString(address(usdBcFeeVault)), '",');
        json = string.concat(json, '"name": "Fee USDbC Vault",');
        json = string.concat(json, '"symbol": "fUSDbC"');
        json = string.concat(json, "}");

        json = string.concat(json, "}");

        // Create deployments directory if needed
        vm.writeJson(json, deployFile);
    }
}
