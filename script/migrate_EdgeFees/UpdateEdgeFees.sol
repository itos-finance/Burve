// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {IRFTPayer, RFTPayer} from "Commons/Util/RFT.sol";
import {TransferHelper} from "../../src/TransferHelper.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract UpdateEdgeFees {
    // 0.05% in X128 format
    uint128 constant NEW_EDGE_FEE_X128 = 170141183460469231731687303715884105; // 0.0005 * 2^128
    // 8% in X128 format: 0.08 * 2^128
    uint128 constant PROTOCOL_TAKE_X128 =
        27222589353675077077069968594541456916; // 0.08 * 2^128

    address constant DIAMOND =
        address(0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089);
    address constant MULTISIG =
        address(0x9293f9FFC43F6fce06290285919541E963D87F51);

    address[] public tokens;
    uint256[] public efactors;

    IBurveMultiSimplex simplexFacet;
    BaseAdminFacet adminFacet;

    constructor() {
        simplexFacet = IBurveMultiSimplex(DIAMOND);
        adminFacet = BaseAdminFacet(DIAMOND);

        tokens = [
            0x549943e04f40284185054145c6E4e9568C1D3241,
            0x779Ded0c9e1022225f8E0630b35a9b54bE713736,
            0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce,
            0x1cE0a25D13CE4d52071aE7e02Cf1F6606F4C79d3,
            0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34,
            0xff12470a969Dd362EB6595FFB44C82c959Fe9ACc,
            0xEDB5180661F56077292C92Ab40B1AC57A279a396,
            0x09D4214C03D01F49544C0448DBE3A27f768F2b34,
            0x688e72142674041f8f6Af4c808a4045cA1D6aC82
        ];

        // Initialize efactors from usd.json
        efactors = [2000, 1500, 500, 333, 660, 100, 50, 200, 1500];
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

        // Update specific edge fees only
        simplexFacet.setEdgeFee(0, 1, NEW_EDGE_FEE_X128);
        simplexFacet.setEdgeFee(1, 2, NEW_EDGE_FEE_X128);
        simplexFacet.setEdgeFee(0, 2, NEW_EDGE_FEE_X128);

        // Update EX128 values for all tokens
        updateAllEX128();
    }

    function updateAllEX128() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _setEX128(tokens[i], efactors[i]);
        }
    }

    function _setEX128(address token, uint256 efactor) internal {
        // Convert efactor to X128 format: efactor * 2^128
        uint256 eX128 = efactor << 128;
        // Set maxSpend to 0 for now (can be adjusted if needed)
        uint256 maxSpend = type(uint256).max;

        TransferHelper.safeApprove(token, DIAMOND, type(uint256).max);

        simplexFacet.setEX128(token, eX128, maxSpend);
    }
}
