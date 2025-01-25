// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {LiqFacet} from "./multi/facets/LiqFacet.sol";
import {SimplexFacet} from "./multi/facets/SimplexFacet.sol";
import {SwapFacet} from "./multi/facets/SwapFacet.sol";

library BurveDeploymentLib {
    /**
     * Deploys each of the facets for the Burve diamond
     */
    function deployFacets()
        internal
        returns (address liqFacet, address simplexFacet, address swapFacet)
    {
        liqFacet = address(new LiqFacet());
        simplexFacet = address(new SimplexFacet());
        swapFacet = address(new SwapFacet());
    }
}
