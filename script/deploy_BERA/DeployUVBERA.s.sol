// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {DeployNoopBase} from "../base/DeployNoopBase.s.sol";

contract DeployUVBERA is DeployNoopBase {
    function tokenAddress() internal pure override returns (address) {
        return 0x1852DEe9680A43Dc79c4Ef49C083bEe24b741a87; // uvBERA
    }

    function vaultName() internal pure override returns (string memory) {
        return "noopUVBERA";
    }

    function vaultSymbol() internal pure override returns (string memory) {
        return "noUVBERA";
    }
}
