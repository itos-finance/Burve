// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./utils/BaseScript.sol";

contract UpdateSimplexFeesScript is BaseScript {
    function run() external {
        setUp(); // Initialize all contracts and arrays

        uint256 deployerKey = _getPrivateKey();

        // Calculate X128 values for 0.5% and 0.15%
        uint256 x128 = uint256(1) << 128;
        uint128 fee1 = uint128((x128 * 5) / 1000); // 0.5%
        uint128 fee2 = uint128((x128 * 15) / 10000); // 0.15%

        vm.startBroadcast(deployerKey);
        simplexFacet.setSimplexFees(fee1, fee2);
        vm.stopBroadcast();

        console2.log("Simplex fees updated:");
        console2.log("fee1 (0.5% X128):", fee1);
        console2.log("fee2 (0.15% X128):", fee2);
    }
}
