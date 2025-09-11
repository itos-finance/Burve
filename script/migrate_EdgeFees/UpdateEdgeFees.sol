// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";

contract UpdateEdgeFees {
    // 0.005% in X128 format: 0.00005 * 2^128
    uint128 constant NEW_EDGE_FEE_X128 = 17014118346046923988514818429550592; // 0.00005 * 2^128
    // 8% in X128 format: 0.08 * 2^128
    uint128 constant PROTOCOL_TAKE_X128 =
        27222589353675077077069968594541456916; // 0.08 * 2^128

    address constant DIAMOND =
        address(0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089);
    address constant MULTISIG =
        address(0x9293f9FFC43F6fce06290285919541E963D87F51);

    IBurveMultiSimplex simplexFacet;
    BaseAdminFacet adminFacet;

    constructor() {
        simplexFacet = IBurveMultiSimplex(DIAMOND);
        adminFacet = BaseAdminFacet(DIAMOND);
    }

    function acceptOwnership() external {
        adminFacet.acceptOwnership();
    }

    function transferOwnership() external {
        adminFacet.transferOwnership(MULTISIG);
    }

    function updateAllEdgeFees() external {
        // Update the default edge fee and protocol take
        simplexFacet.setSimplexFees(NEW_EDGE_FEE_X128, PROTOCOL_TAKE_X128); // Protocol take isnt changing

        // Get the number of vertices
        uint8 numVertices = simplexFacet.getNumVertices();

        // Update all edge fees
        for (uint8 i = 0; i < numVertices; i++) {
            for (uint8 j = i + 1; j < numVertices; j++) {
                simplexFacet.setEdgeFee(i, j, NEW_EDGE_FEE_X128);
            }
        }
    }
}
