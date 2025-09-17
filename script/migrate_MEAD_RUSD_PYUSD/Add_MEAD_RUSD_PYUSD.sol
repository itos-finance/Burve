// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {VaultType} from "../../src/multi/vertex/VaultProxy.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";

contract Add_MEAD_RUSD_PYUSD {
    // when using the min initial value, 1e12, too many 1 token deposits into dolomite causes issues in the same transaction, so we use 1e13
    uint128 constant INITIAL_VALUE = 1e13;

    address constant DIAMOND =
        address(0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089);
    address constant MULTISIG =
        address(0x9293f9FFC43F6fce06290285919541E963D87F51);
    address constant FUNDER =
        address(0xbe7dC5cC7977ac378ead410869D6c96f1E6C773e);

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

    function deployMEAD() external {
        address token = 0xEDB5180661F56077292C92Ab40B1AC57A279a396;
        address vault = 0x82576213872683791B9f779cf788a6D478651C78; // noop vault deployed by us
        uint256 efactor = 18;

        simplexFacet.addVertex(token, vault, VaultType.E4626);

        // set efficiency factors
        simplexFacet.setEX128(token, efactor << 128, 0);
    }

    function deployRUSD() external {
        address token = 0x09D4214C03D01F49544C0448DBE3A27f768F2b34;
        address vault = 0x3000C6BF0AAEb813e252B584c4D9a82f99e7a71D;
        uint256 efactor = 150;

        simplexFacet.addVertex(token, vault, VaultType.E4626);

        // set efficiency factors
        simplexFacet.setEX128(token, efactor << 128, 0);
    }

    function deployPYUSD() external {
        address token = 0x688e72142674041f8f6Af4c808a4045cA1D6aC82;
        address vault = 0x2948609CdD0ac4110b63165be9D4AADe66bF40F6;
        uint256 efactor = 150;

        simplexFacet.addVertex(token, vault, VaultType.E4626);

        // set efficiency factors
        simplexFacet.setEX128(token, efactor << 128, 0);
    }

    function initializeClosure(uint16 minClosure, uint16 maxClosure) external {
        address[] memory tokens = simplexFacet.getTokens();

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).approve(address(simplexFacet), type(uint256).max);
        }

        for (uint16 cid = minClosure; cid < maxClosure; cid++) {
            simplexFacet.addClosure(cid, INITIAL_VALUE);
        }
    }

    function returnBalances() external {
        address[] memory tokens = simplexFacet.getTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            IERC20(tokens[i]).transfer(FUNDER, balance);
        }
    }
}
