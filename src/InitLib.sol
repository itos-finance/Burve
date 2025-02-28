// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {LiqFacet} from "./multi/facets/LiqFacet.sol";
import {SimplexFacet} from "./multi/facets/SimplexFacet.sol";
import {SwapFacet} from "./multi/facets/SwapFacet.sol";
import {VaultFacet} from "./multi/facets/VaultFacet.sol";
import {DecimalAdjustor} from "./integrations/adjustor/DecimalAdjustor.sol";

struct BurveFacets {
    address liqFacet;
    address simplexFacet;
    address swapFacet;
    address vaultFacet;
    address adjustor;
}

library InitLib {
    /**
     * Deploys each of the facets for the Burve diamond
     */
    function deployFacets() internal returns (BurveFacets memory facets) {
        facets.liqFacet = address(new LiqFacet());
        facets.simplexFacet = address(new SimplexFacet());
        facets.swapFacet = address(new SwapFacet());
        facets.vaultFacet = address(new VaultFacet());
        facets.adjustor = address(new DecimalAdjustor());
    }
}
