// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";

contract WithdrawFees is BaseScript {
    // Modify these parameters as needed
    address constant TOKEN =
        address(0x2E2Ed0Cfd3AD2f1d34481277b3204d807Ca2F8c2); // e.g. USDC
    uint256 constant AMOUNT = 1; // Amount in token's smallest unit (e.g. 1 USDC = 1000000)

    function run() external {
        // Start broadcasting
        vm.startBroadcast(_getPrivateKey());

        // Withdraw protocol fees
        simplexFacet.withdrawFees(TOKEN, AMOUNT);

        console2.log("Protocol fees withdrawn:");
        console2.log("Token:", TOKEN);
        console2.log("Amount:", AMOUNT);

        vm.stopBroadcast();
    }
}
