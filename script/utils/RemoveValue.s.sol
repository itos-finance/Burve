// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";
import {ClosureId} from "../../src/multi/closure/Id.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";

contract RemoveValue is BaseScript {
    function run() external {
        // Load configuration from environment
        address recipient = vm.envOr("RECIPIENT", _getSender());
        uint16 closureId = uint16(vm.envOr("CLOSURE_ID", uint256(0)));
        uint128 valueAmount = uint128(vm.envOr("VALUE", uint256(0)));
        uint128 bgtValue = uint128(vm.envOr("BGT_VALUE", uint256(valueAmount))); // Default to full value if not specified

        // Start broadcasting
        vm.startBroadcast(_getPrivateKey());

        console2.log("\nPreparing to remove value:");
        console2.log("Closure ID:", closureId);
        console2.log("Value to remove:", valueAmount);
        console2.log("BGT Value:", bgtValue);
        console2.log("Recipient:", recipient);

        // Remove value from the closure
        uint256[MAX_TOKENS] memory receivedBalances = valueFacet.removeValue(
            recipient,
            closureId,
            valueAmount,
            bgtValue
        );

        // Log the received balances for each token
        console2.log("\nReceived balances:");
        for (uint8 i = 0; i < MAX_TOKENS; i++) {
            if (receivedBalances[i] > 0) {
                address token = _getTokenByIndex(i);
                console2.log(
                    string.concat(
                        "Token ",
                        vm.toString(i),
                        " (",
                        MockERC20(token).symbol(),
                        "): ",
                        vm.toString(receivedBalances[i])
                    )
                );
            }
        }

        vm.stopBroadcast();
    }
}
