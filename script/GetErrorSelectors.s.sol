// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";

/**
 * @title GetErrorSelectors
 * @notice Script to extract error selectors from contracts
 * @dev Run with: forge script script/GetErrorSelectors.s.sol
 */
contract GetErrorSelectors is Script {
    function run() external view {
        // Example: Get selector for a specific error
        bytes4 selector1 = this.getErrorSelector.selector;
        
        // For actual errors, you need to compute them manually
        // Error selector = first 4 bytes of keccak256("ErrorName(type1,type2)")
        
        console.log("=== Error Selector Examples ===");
        console.log("Use 'cast sig' command for individual errors:");
        console.log("  cast sig \"InsecureFirstMintAmount(uint256)\"");
        console.log("");
        console.log("Or use 'cast interface' to see all errors in a contract:");
        console.log("  cast interface src/integrations/BRC20.sol");
    }
    
    // Helper function to demonstrate selector calculation
    function getErrorSelector(string memory errorSig) external pure returns (bytes4) {
        return bytes4(keccak256(bytes(errorSig)));
    }
}

