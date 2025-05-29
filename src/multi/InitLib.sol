// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ValueFacet, ValueSingleFacet} from "./facets/ValueFacet.sol";
import {AddTokenValueFacet, RemoveTokenValueFacet, QueryValueFacet} from "./facets/ValueFacet.sol";
import {ValueTokenFacet} from "./facets/ValueTokenFacet.sol";
import {SimplexAdminFacet, SimplexSetFacet, SimplexGetFacet} from "./facets/SimplexFacet.sol";
import {SwapFacet} from "./facets/SwapFacet.sol";
import {VaultFacet} from "./facets/VaultFacet.sol";
import {DecimalAdjustor} from "../integrations/adjustor/DecimalAdjustor.sol";

struct BurveFacets {
    // Value facets
    address valueFacet;
    address valueSingleFacet;
    address addTokenValueFacet;
    address removeTokenValueFacet;
    address queryValueFacet;
    // Simplex facets
    address simplexAdminFacet;
    address simplexSetFacet;
    address simplexGetFacet;
    // Non-value facets
    address valueTokenFacet;
    address swapFacet;
    address vaultFacet;
    address adjustor;
}

library InitLib {
    /**
     * Deploys each of the facets for the Burve diamond
     */
    function deployFacets() internal returns (BurveFacets memory facets) {
        facets.valueFacet = address(new ValueFacet());
        facets.valueSingleFacet = address(new ValueSingleFacet());
        facets.addTokenValueFacet = address(new AddTokenValueFacet());
        facets.removeTokenValueFacet = address(new RemoveTokenValueFacet());
        facets.queryValueFacet = address(new QueryValueFacet());

        facets.simplexAdminFacet = address(new SimplexAdminFacet());
        facets.simplexSetFacet = address(new SimplexSetFacet());
        facets.simplexGetFacet = address(new SimplexGetFacet());

        facets.valueFacet = address(new ValueFacet());
        facets.valueTokenFacet = address(new ValueTokenFacet());
        facets.swapFacet = address(new SwapFacet());
        facets.vaultFacet = address(new VaultFacet());
        facets.adjustor = address(new DecimalAdjustor());
    }
}
