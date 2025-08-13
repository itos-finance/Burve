// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {DeployNoopBase} from "../base/DeployNoopBase.s.sol";

contract DeployFATBERA is DeployNoopBase {
    function tokenAddress() internal pure override returns (address) {
        return 0xBAE11292A3E693aF73651BDa350D752AE4A391D4; // FATBERA
    }

    function vaultName() internal pure override returns (string memory) {
        return "noopFATBERA";
    }

    function vaultSymbol() internal pure override returns (string memory) {
        return "noFATBERA";
    }
}
