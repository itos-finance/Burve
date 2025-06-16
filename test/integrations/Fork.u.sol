// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ForkableTest} from "../../lib/Commons/src/Test/ForkableTest.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {VaultType} from "../../src/multi/vertex/VaultProxy.sol";
import {InitLib, BurveFacets} from "../../src/multi/InitLib.sol";
import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {IBurveMultiValue} from "../../src/multi/interfaces/IBurveMultiValue.sol";
import {ValueTokenFacet} from "../../src/multi/facets/ValueTokenFacet.sol";
import {VaultFacet} from "../../src/multi/facets/VaultFacet.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {LockFacet} from "../../src/multi/facets/LockFacet.sol";
import {StoreManipulatorFacet} from "../facets/StoreManipulatorFacet.u.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract BurveForkableTest is ForkableTest {
    // Diamond and facets
    address public diamond;
    IBurveMultiValue public valueFacet;
    ValueTokenFacet public valueTokenFacet;
    VaultFacet public vaultFacet;
    IBurveMultiSimplex public simplexFacet;
    SwapFacet public swapFacet;
    LockFacet public lockFacet;
    StoreManipulatorFacet public storeManipulatorFacet;

    // Token and vault arrays
    address[] public tokens;
    address[] public vaults;

    // Accounts
    address public owner;
    address public alice;
    address public bob;

    string public envFile = "script/berachain/btc.json";

    function preSetup() internal override {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
    }

    function deploySetup() internal override {
        // Deploy diamond and facets
        BurveFacets memory bFacets = InitLib.deployFacets();
        diamond = address(new SimplexDiamond(bFacets, "ValueToken", "BVT"));
        valueFacet = IBurveMultiValue(diamond);
        valueTokenFacet = ValueTokenFacet(diamond);
        vaultFacet = VaultFacet(diamond);
        simplexFacet = IBurveMultiSimplex(diamond);
        swapFacet = SwapFacet(diamond);
        lockFacet = LockFacet(diamond);

        string memory envJson = vm.readFile(envFile);
        tokens = vm.parseJsonAddressArray(envJson, ".tokens");
        vaults = vm.parseJsonAddressArray(envJson, ".vaults");

        simplexFacet.addVertex(tokens[0], vaults[0], VaultType.E4626);
        simplexFacet.addVertex(tokens[1], vaults[1], VaultType.E4626);
        simplexFacet.addVertex(tokens[2], vaults[2], VaultType.E4626);

        _initializeClosure(0x3, 1e18);
        _initializeClosure(0x4, 1e18);
        _initializeClosure(0x5, 1e18);
        _initializeClosure(0x6, 1e18);
        _initializeClosure(0x7, 1e18);
    }

    function forkSetup() internal override {
        // Deploy diamond and facets
        BurveFacets memory bFacets = InitLib.deployFacets();
        diamond = address(new SimplexDiamond(bFacets, "ValueToken", "BVT"));
        valueFacet = IBurveMultiValue(diamond);
        valueTokenFacet = ValueTokenFacet(diamond);
        vaultFacet = VaultFacet(diamond);
        simplexFacet = IBurveMultiSimplex(diamond);
        swapFacet = SwapFacet(diamond);
        lockFacet = LockFacet(diamond);

        string memory envJson = vm.readFile(envFile);
        tokens = vm.parseJsonAddressArray(envJson, ".tokens");
        vaults = vm.parseJsonAddressArray(envJson, ".vaults");

        simplexFacet.addVertex(tokens[0], vaults[0], VaultType.E4626);
        simplexFacet.addVertex(tokens[1], vaults[1], VaultType.E4626);
        simplexFacet.addVertex(tokens[2], vaults[2], VaultType.E4626);

        _initializeClosure(0x3, 1e18);
        _initializeClosure(0x4, 1e18);
        _initializeClosure(0x5, 1e18);
        _initializeClosure(0x6, 1e18);
        _initializeClosure(0x7, 1e18);
    }

    /// Initalize a zero fee closure with the initial value amount.
    function _initializeClosure(uint16 cid, uint128 initValue) internal {
        // Mint ourselves enough to fund the initial target of the pool.
        for (uint256 i = 0; i < tokens.length; ++i) {
            if ((1 << i) & cid > 0) {
                deal(tokens[i], address(this), initValue);
                IERC20(tokens[i]).approve(address(diamond), type(uint256).max);
            }
        }
        simplexFacet.addClosure(cid, initValue);
    }
}
