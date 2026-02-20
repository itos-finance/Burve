// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ForkableTest} from "../../lib/Commons/src/Test/ForkableTest.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
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
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";

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

    string public envFile = "script/berachain/usd.json";

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

        // Deploy 3 mock tokens
        for (uint8 i = 0; i < 3; i++) {
            string memory idx = Strings.toString(i);
            tokens.push(
                address(
                    new MockERC20(
                        string.concat("Test Token ", idx),
                        string.concat("TEST", idx),
                        18
                    )
                )
            );
        }

        // Sort tokens ascending (required by addVertex)
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                if (tokens[i] > tokens[j]) {
                    (tokens[i], tokens[j]) = (tokens[j], tokens[i]);
                }
            }
        }

        // Deploy mock ERC4626 vaults and add vertices
        for (uint256 i = 0; i < 3; i++) {
            string memory idx = Strings.toString(i);
            address vault = address(
                new MockERC4626(
                    ERC20(tokens[i]),
                    string.concat("Vault ", idx),
                    string.concat("V", idx)
                )
            );
            vaults.push(vault);
            simplexFacet.addVertex(tokens[i], vault, VaultType.E4626);
        }

        _initializeClosure(0x3, 1e18);
        _initializeClosure(0x4, 1e18);
        _initializeClosure(0x5, 1e18);
        _initializeClosure(0x6, 1e18);
        _initializeClosure(0x7, 1e18);
    }

    function forkSetup() internal override {
        // Deploy diamond and facets
        diamond = address(0xa1beD164c12CD9479A1049f97BDe5b3D6EC21089);
        valueFacet = IBurveMultiValue(diamond);
        valueTokenFacet = ValueTokenFacet(diamond);
        vaultFacet = VaultFacet(diamond);
        simplexFacet = IBurveMultiSimplex(diamond);
        swapFacet = SwapFacet(diamond);
        lockFacet = LockFacet(diamond);
        tokens = simplexFacet.getTokens();
    }

    /// Initalize a zero fee closure with the initial value amount.
    function _initializeClosure(uint16 cid, uint128 initValue) internal {
        // Mint ourselves enough to fund the initial target of the pool.
        for (uint256 i = 0; i < tokens.length; ++i) {
            if ((1 << i) & cid > 0) {
                MockERC20(tokens[i]).mint(address(this), initValue);
                IERC20(tokens[i]).approve(address(diamond), type(uint256).max);
            }
        }
        simplexFacet.addClosure(cid, initValue);
    }
}
