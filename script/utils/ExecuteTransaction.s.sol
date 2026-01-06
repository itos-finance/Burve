// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract ExecuteTransaction is Script {
    function run() external {
        address from = 0xE57Ec670263F20bf40d9d53831a42D0D9eEbBcAe;
        address to = 0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089;
        bytes
            memory data = hex"d55f94f5000000000000000000000000e57ec670263f20bf40d9d53831a42d0d9eebbcae000000000000000000000000688e72142674041f8f6af4c808a4045ca1d6ac820000000000000000000000005d3a1ff2b6bab83b63cd9ad0787074081a52ef340000000000000000000000000000000000000000000000071ee7a8fc07eb80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000019f";
        uint256 value = 0;

        // Get private key from environment (you'll need to set this)
        uint256 privateKey = 0xd2110485635b3163eb684f5dd1c14b256f0256c743eb3086c3f14cc38e79ce71; // vm.envUint("PRIVATE_KEY");
        require(
            vm.addr(privateKey) == from,
            "Private key does not match from address"
        );

        console2.log("Executing transaction:");
        console2.log("From:", from);
        console2.log("To:", to);
        console2.log("Value:", value);

        // Start broadcasting with the private key
        vm.startBroadcast(privateKey);

        // Execute the transaction
        (bool success, bytes memory returnData) = to.call{value: value}(data);

        require(success, "Transaction failed");

        console2.log("Transaction executed successfully");
        console2.log("Return data length:", returnData.length);

        vm.stopBroadcast();
    }
}
