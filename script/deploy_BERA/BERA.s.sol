// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BaseDeployFromEnv} from "../base/DeployBase.s.sol";

contract DeployBERA is BaseDeployFromEnv {
    function valueTokenName() internal pure override returns (string memory) {
        return "BERAValueToken";
    }

    function valueTokenSymbol() internal pure override returns (string memory) {
        return "BBVT";
    }

    function envPath() internal pure override returns (string memory) {
        return "script/berachain/usd.json";
    }

    function deployPath() internal pure override returns (string memory) {
        return "script/berachain/deployments/usd.json";
    }

    function configureSimplexFees() internal override {
        simplexFacet.setSimplexFees(
            136112946768375385385349842972707284,
            27222589353675077077069968594541456916
        );
    }
}
