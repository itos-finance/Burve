// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {AdminLib} from "Commons/Util/Admin.sol";

import {IAdjustor} from "../../src/integrations/adjustor/IAdjustor.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MultiSetupTest} from "./MultiSetup.u.sol";
import {SearchParams} from "../../src/multi/Value.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {Simplex, SimplexLib} from "../../src/multi/Simplex.sol";
import {NullAdjustor} from "../../src/integrations/adjustor/NullAdjustor.sol";

contract SimplexFacetTest is MultiSetupTest {
    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(3);
        vm.stopPrank();
    }

    // -- withdraw tests ----

    function testWithdrawRegisteredTokenWithEarnedFeesAndDonation() public {
        vm.startPrank(owner);

        // simulate earned fees and donation
        IERC20 token = IERC20(tokens[0]);
        deal(address(token), diamond, 8e18);

        uint256[MAX_TOKENS] memory protocolEarnings;
        protocolEarnings[0] = 7e18;
        storeManipulatorFacet.setProtocolEarnings(protocolEarnings);

        // record balances
        uint256 ownerBalance = token.balanceOf(owner);
        uint256 protocolBalance = token.balanceOf(diamond);
        assertGe(protocolBalance, 7e18);

        // withdraw
        vm.expectEmit(true, false, false, true);
        emit SimplexFacet.FeesWithdrawn(address(token), 8e18, 7e18);
        simplexFacet.withdraw(address(token));

        // check balances
        assertEq(token.balanceOf(owner), ownerBalance + protocolBalance);
        assertEq(token.balanceOf(diamond), 0);

        // check protocol earnings
        protocolEarnings = SimplexLib.protocolEarnings();
        assertEq(protocolEarnings[0], 0);

        vm.stopPrank();
    }

    function testWithdrawRegisteredTokenWithEarnedFees() public {
        vm.startPrank(owner);

        // simulate earned fees
        IERC20 token = IERC20(tokens[0]);
        deal(address(token), diamond, 7e18);

        uint256[MAX_TOKENS] memory protocolEarnings;
        protocolEarnings[0] = 7e18;
        storeManipulatorFacet.setProtocolEarnings(protocolEarnings);

        // record balances
        uint256 ownerBalance = token.balanceOf(owner);
        uint256 protocolBalance = token.balanceOf(diamond);
        assertGe(protocolBalance, 7e18);

        // withdraw
        vm.expectEmit(true, false, false, true);
        emit SimplexFacet.FeesWithdrawn(address(token), 7e18, 7e18);
        simplexFacet.withdraw(address(token));

        // check balances
        assertEq(token.balanceOf(owner), ownerBalance + protocolBalance);
        assertEq(token.balanceOf(diamond), 0);
        // check protocol earnings
        protocolEarnings = SimplexLib.protocolEarnings();
        assertEq(protocolEarnings[0], 0);

        vm.stopPrank();
    }

    function testWithdrawRegisteredTokenWithoutEarnedFees() public {
        vm.startPrank(owner);

        // simulate donation
        IERC20 token = IERC20(tokens[0]);
        deal(address(token), diamond, 1e18);

        // record balances
        uint256 ownerBalance = token.balanceOf(owner);
        uint256 protocolBalance = token.balanceOf(diamond);
        assertGe(protocolBalance, 1e18);

        // withdraw
        vm.expectEmit(true, false, false, true);
        emit SimplexFacet.FeesWithdrawn(address(token), 1e18, 0);
        simplexFacet.withdraw(address(token));

        // check balances
        assertEq(token.balanceOf(owner), ownerBalance + protocolBalance);
        assertEq(token.balanceOf(diamond), 0);

        vm.stopPrank();
    }

    function testWithdrawUnregisteredToken() public {
        vm.startPrank(owner);

        // simulate donation
        MockERC20 unregisteredToken = new MockERC20(
            "Unregistered",
            "UNREG",
            18
        );
        deal(address(unregisteredToken), diamond, 10e18);

        // record balances
        uint256 ownerBalance = unregisteredToken.balanceOf(owner);
        uint256 protocolBalance = unregisteredToken.balanceOf(diamond);
        assertGe(protocolBalance, 10e18);

        // withdraw
        simplexFacet.withdraw(address(unregisteredToken));

        // check balances
        assertEq(
            unregisteredToken.balanceOf(owner),
            ownerBalance + protocolBalance
        );
        assertEq(unregisteredToken.balanceOf(diamond), 0);

        vm.stopPrank();
    }

    function testRevertWithdrawNotOwner() public {
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.withdraw(tokens[0]);
    }

    // -- esX128 tests ----

    function testEsX128Default() public {
        uint256[MAX_TOKENS] memory esX128 = simplexFacet.getEsX128();
        for (uint256 i = 0; i < MAX_TOKENS; i++) {
            assertEq(esX128[i], 10 << 128);
        }
    }

    function testGetEX128Default() public {
        uint256 esX128 = simplexFacet.getEX128(tokens[0]);
        assertEq(esX128, 10 << 128);

        esX128 = simplexFacet.getEX128(tokens[1]);
        assertEq(esX128, 10 << 128);
    }

    function testSetEX128() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, false, true);
        emit SimplexFacet.EfficiencyFactorChanged(
            owner,
            tokens[1],
            10 << 128,
            20 << 128
        );
        simplexFacet.setEX128(tokens[1], 20 << 128);

        uint256 esX128 = simplexFacet.getEX128(tokens[1]);
        assertEq(esX128, 20 << 128);

        vm.stopPrank();
    }

    function testRevertSetEX128NotOwner() public {
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.setEX128(tokens[0], 1);
    }

    // -- adjustor tests ----

    function testGetAdjustorDefault() public {
        assertNotEq(simplexFacet.getAdjustor(), address(0x0));
    }

    function testSetAdjustor() public {
        vm.startPrank(owner);

        // set adjustor A
        address adjustorA = address(new NullAdjustor());

        // check caching
        for (uint8 i = 0; i < tokens.length; ++i) {
            vm.expectCall(
                adjustorA,
                abi.encodeCall(IAdjustor.cacheAdjustment, (tokens[i]))
            );
        }

        // check change event
        vm.expectEmit(true, false, false, true);
        emit SimplexFacet.AdjustorChanged(
            owner,
            simplexFacet.getAdjustor(),
            adjustorA
        );

        simplexFacet.setAdjustor(adjustorA);
        assertEq(simplexFacet.getAdjustor(), adjustorA);

        // set adjustor B
        address adjustorB = address(new NullAdjustor());

        // check caching
        for (uint8 i = 0; i < tokens.length; ++i) {
            vm.expectCall(
                adjustorB,
                abi.encodeCall(IAdjustor.cacheAdjustment, (tokens[i]))
            );
        }

        // check change event
        vm.expectEmit(true, false, false, true);
        emit SimplexFacet.AdjustorChanged(owner, adjustorA, adjustorB);

        simplexFacet.setAdjustor(adjustorB);
        assertEq(simplexFacet.getAdjustor(), adjustorB);

        vm.stopPrank();
    }

    function testRevertSetAdjustorDoesNotImplementIAdjustor() public {
        // setAdjustor does not verify the entire interface
        // this will pass / fail for an address if they implement / don't implement cacheAdjustment
        vm.startPrank(owner);
        vm.expectRevert();
        simplexFacet.setAdjustor(makeAddr("adjustor"));
        vm.stopPrank();
    }

    function testRevertSetAdjustorIsZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert();
        simplexFacet.setAdjustor(address(0));
        vm.stopPrank();
    }

    function testRevertSetAdjustorNotOwner() public {
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.setAdjustor(address(0));
    }

    // -- searchParams tests ----

    function testGetSearchParams() public {
        SearchParams memory sp = simplexFacet.getSearchParams();
        assertEq(sp.maxIter, 5);
        assertEq(sp.deMinimusX128, 100);
        assertEq(sp.targetSlippageX128, 1e12);
    }

    function testSetSearchParams() public {
        vm.startPrank(owner);

        SearchParams memory sp = SearchParams(10, 500, 1e18);

        vm.expectEmit(true, false, false, true);
        emit SimplexFacet.SearchParamsChanged(
            owner,
            sp.maxIter,
            sp.deMinimusX128,
            sp.targetSlippageX128
        );
        simplexFacet.setSearchParams(sp);

        SearchParams memory sp2 = simplexFacet.getSearchParams();
        assertEq(sp2.maxIter, sp.maxIter);
        assertEq(sp2.deMinimusX128, sp.deMinimusX128);
        assertEq(sp2.targetSlippageX128, sp.targetSlippageX128);

        vm.stopPrank();
    }

    function testRevertSetSearchParamsDeMinimusIsZero() public {
        vm.startPrank(owner);

        SearchParams memory sp = SearchParams(10, 0, 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                SimplexFacet.NonPositiveDeMinimusX128.selector,
                sp.deMinimusX128
            )
        );
        simplexFacet.setSearchParams(sp);

        vm.stopPrank();
    }

    function testRevertSetSearchParamsDeMinimusIsNegative() public {
        vm.startPrank(owner);

        SearchParams memory sp = SearchParams(10, -100, 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                SimplexFacet.NonPositiveDeMinimusX128.selector,
                sp.deMinimusX128
            )
        );
        simplexFacet.setSearchParams(sp);

        vm.stopPrank();
    }

    function testRevertSetSearchParamsNotOwner() public {
        SearchParams memory sp = SearchParams(10, 5, 1e4);
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.setSearchParams(sp);
    }
}

/* import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BurveFacets, InitLib} from "../../src/multi/InitLib.sol";
import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {VaultType, VaultLib} from "../../src/multi/vertex/VaultProxy.sol";
import {Store} from "../../src/multi/Store.sol";
import {VertexId, VertexLib} from "../../src/multi/vertex/Id.sol";
import {TokenRegLib} from "../../src/multi/Token.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
// Adjustment test imports
import {MultiSetupTest} from "./MultiSetup.u.sol";
import {NullAdjustor} from "../../src/integrations/adjustor/NullAdjustor.sol";
import {IAdjustor} from "../../src/integrations/adjustor/IAdjustor.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract SimplexFacetTest is Test {
    SimplexDiamond public diamond;
    EdgeFacet public edgeFacet;
    SimplexFacet public simplexFacet;
    ViewFacet public viewFacet;

    MockERC20 public token0;
    MockERC20 public token1;
    MockERC4626 public mockVault0;
    MockERC4626 public mockVault1;

    address public owner = makeAddr("owner");
    address public nonOwner = makeAddr("nonOwner");

    event VertexAdded(
        address indexed token,
        address vault,
        VaultType vaultType
    );
    event EdgeUpdated(
        address indexed token0,
        address indexed token1,
        uint256 amplitude,
        int24 lowTick,
        int24 highTick
    );

    function setUp() public {
        vm.startPrank(owner);

        // Deploy the diamond and facets
        BurveFacets memory facets = InitLib.deployFacets();
        diamond = new SimplexDiamond(facets);

        edgeFacet = EdgeFacet(address(diamond));
        simplexFacet = SimplexFacet(address(diamond));
        viewFacet = ViewFacet(address(diamond));

        // Setup test tokens
        token0 = new MockERC20("Test Token 0", "TEST0", 18);
        token1 = new MockERC20("Test Token 1", "TEST1", 18);

        mockVault0 = new MockERC4626(token0, "Mock Vault 0", "MVLT0");
        mockVault1 = new MockERC4626(token1, "Mock Vault 1", "MVLT1");

        vm.stopPrank();
    }

    function testAddVertex() public {
        vm.startPrank(owner);

        // Add first vertex
        simplexFacet.addVertex(
            address(token0),
            address(mockVault0),
            VaultType.E4626
        );

        // Add second vertex
        simplexFacet.addVertex(
            address(token1),
            address(mockVault1),
            VaultType.E4626
        );

        vm.stopPrank();
    }

    function testAddVertexRevertUnimplemented() public {
        vm.startPrank(owner);

        // Add first vertex
        vm.expectRevert(
            abi.encodeWithSelector(VaultLib.VaultTypeNotRecognized.selector, 0)
        );
        simplexFacet.addVertex(
            address(token0),
            address(0),
            VaultType.UnImplemented
        );

        // Add second vertex
        vm.expectRevert(
            abi.encodeWithSelector(VaultLib.VaultTypeNotRecognized.selector, 0)
        );
        simplexFacet.addVertex(
            address(token1),
            address(0),
            VaultType.UnImplemented
        );

        vm.stopPrank();
    }

    function testAddVertexRevertNonOwner() public {
        vm.startPrank(nonOwner);

        vm.expectRevert();
        simplexFacet.addVertex(
            address(token0),
            address(mockVault0),
            VaultType.E4626
        );

        vm.stopPrank();
    }

    function testAddVertexRevertsForDuplicate() public {
        vm.startPrank(owner);

        // Add vertex first time
        simplexFacet.addVertex(
            address(token0),
            address(mockVault0),
            VaultType.E4626
        );

        // Try to add same vertex again
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenRegistryImpl.TokenAlreadyRegistered.selector,
                address(token0)
            )
        ); // Should revert for duplicate vertex
        simplexFacet.addVertex(
            address(token0),
            address(mockVault0),
            VaultType.E4626
        );

        vm.stopPrank();
    }
}

contract SimplexFacetAdjustorTest is MultiSetupTest {
    function setUp() public {
        _newDiamond();
        _newTokens(2);

        // Add a 6 decimal token.
        tokens.push(address(new MockERC20("Test Token 3", "TEST3", 6)));
        vaults.push(
            IERC4626(
                address(new MockERC4626(ERC20(tokens[2]), "vault 3", "V3"))
            )
        );
        simplexFacet.addVertex(tokens[2], address(vaults[2]), VaultType.E4626);

        _fundAccount(address(this));
    }

    /// Test that switching the adjustor actually works on setAdjustment by testing
    /// the liquidity value of the same deposit.
    function testSetAdjustor() public {
        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 1e18;
        amounts[1] = 1e18;
        amounts[2] = 1e6;
        // Init liq, the initial "value" in the pool.
        uint256 initLiq = liqFacet.addLiq(address(this), 0x7, amounts);

        amounts[1] = 0;
        amounts[2] = 0;
        // Adding this still gives close to a third of the "value" in the pool.
        uint256 withAdjLiq = liqFacet.addLiq(address(this), 0x7, amounts);
        assertApproxEqRel(withAdjLiq, initLiq / 3, 1e16); // Off by 1%

        // But if we switch the adjustor. Now it's worth less, although not that much less
        // because even though the balance of token2 is low, its value goes off peg and goes much higher.
        // Therefore it ends up with roughly 1/5th of the pool's value now instead of something closer to 1/4.
        IAdjustor nAdj = new NullAdjustor();
        simplexFacet.setAdjustor(nAdj);
        amounts[0] = 0;
        amounts[1] = 1e18; // Normally this would be close to withAdjLiq.
        uint256 noAdjLiq = liqFacet.addLiq(address(this), 0x7, amounts);
        assertApproxEqRel(noAdjLiq, (initLiq + withAdjLiq) / 5, 1e16); // Off by 1%
    }
} */
