// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;
/*
import "./BaseScript.sol";

contract RemoveLiquidity is BaseScript {
    function run() external {
        // Load configuration from environment
        address recipient = vm.envOr("RECIPIENT", _getSender());
        uint16 closureId = uint16(vm.envUint("CLOSURE_ID"));
        uint256 shares = vm.envUint("SHARES"); // Number of LP shares to burn

        // Start broadcasting
        vm.startBroadcast(_getPrivateKey());

        // Get LP token for this closure
        BurveMultiLPToken lpToken = _getLPToken(closureId);

        // Approve LP token spending
        lpToken.approve(address(diamond), shares);

        // Remove liquidity
        liqFacet.removeLiq(recipient, closureId, shares);

        console2.log("Removed liquidity from closure", closureId);
        console2.log("Shares burned:", shares);
        console2.log("LP Token:", address(lpToken));

        vm.stopBroadcast();
    }
}
 */
