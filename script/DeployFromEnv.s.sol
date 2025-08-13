// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BaseDeployFromEnv} from "./base/DeployBase.s.sol";

contract DeployFromEnv is BaseDeployFromEnv {
    function valueTokenName() internal pure override returns (string memory) {
        return "ValueToken";
    }

    function valueTokenSymbol() internal pure override returns (string memory) {
        return "BVT";
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

    function configureAfterVertices() internal override {
        // .7 bps for USDC, USDT, HONEY routes
        simplexFacet.setEdgeFee(0, 1, 238197656844656924424362225202237748);
        simplexFacet.setEdgeFee(1, 2, 238197656844656924424362225202237748);
        simplexFacet.setEdgeFee(0, 2, 238197656844656924424362225202237748);
    }
}
