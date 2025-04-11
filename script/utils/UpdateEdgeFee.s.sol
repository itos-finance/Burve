// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/* import "./BaseScript.sol";

contract UpdateEdgeFee is BaseScript {
    // Modify these parameters as needed
    address constant TOKEN0 =
        address(0x2E2Ed0Cfd3AD2f1d34481277b3204d807Ca2F8c2); // e.g. USDC
    address constant TOKEN1 =
        address(0xD8a5a9b31c3C0232E196d518E89Fd8bF83AcAd43); // e.g. WETH
    uint24 constant FEE = 500; // 0.05% fee = 500
    uint8 constant FEE_PROTOCOL = 10; // 10% of fees go to protocol

    function run() external {
        // Start broadcasting
        vm.startBroadcast(_getPrivateKey());

        // Update the edge fee
        edgeFacet.setEdgeFee(TOKEN0, TOKEN1, FEE, FEE_PROTOCOL);

        console2.log("Edge fee updated:");
        console2.log("Token0:", TOKEN0);
        console2.log("Token1:", TOKEN1);
        console2.log("New Fee:", FEE);
        console2.log("New Fee Protocol:", FEE_PROTOCOL);

        vm.stopBroadcast();
    }
}
 */
