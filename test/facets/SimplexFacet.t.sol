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
import {TokenRegLib} from "../../src/multi/Token.sol";
import {NullAdjustor} from "../../src/integrations/adjustor/NullAdjustor.sol";
import {VaultType} from "../../src/multi/vertex/VaultProxy.sol";
import {Vertex} from "../../src/multi/vertex/Vertex.sol";
import {VertexId, VertexLib} from "../../src/multi/vertex/Id.sol";

/* For SimplexFacetVertexTest */
import {VaultType, VaultLib} from "../../src/multi/vertex/VaultProxy.sol";
import {TokenRegLib} from "../../src/multi/Token.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
/* For SimplexFacetClosureTest */
import {Store} from "../../src/multi/Store.sol";
import {ClosureId} from "../../src/multi/closure/Id.sol";
import {VertexLib} from "../../src/multi/vertex/Id.sol";

contract SimplexFacetTest is MultiSetupTest {
    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(3);
        vm.stopPrank();
    }

    // -- addVertex tests ----

    function testAddVertex() public {
        vm.startPrank(owner);

        address token = address(new MockERC20("token", "t", 18));
        address vault = makeAddr("vault");
        VertexId vid = VertexLib.newId(3);

        vm.expectEmit(true, true, false, true);
        emit SimplexFacet.VertexAdded(token, vault, vid, VaultType.E4626);
        simplexFacet.addVertex(token, vault, VaultType.E4626);

        // check vertex
        Vertex memory v = storeManipulatorFacet.getVertex(vid);
        assertEq(VertexId.unwrap(v.vid), VertexId.unwrap(vid));
        assertEq(v._isLocked, false);

        // check vault
        (address activeVault, address backupVault) = vaultFacet.viewVaults(
            token
        );
        assertEq(activeVault, vault);
        assertEq(backupVault, address(0x0));

        vm.stopPrank();
    }

    function testRevertAddVertexTokenAlreadyRegistered() public {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenRegLib.TokenAlreadyRegistered.selector,
                tokens[0]
            )
        );
        simplexFacet.addVertex(tokens[0], address(vaults[0]), VaultType.E4626);
        vm.stopPrank();
    }

    function testRevertAddVertexNotOwner() public {
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.addVertex(tokens[0], address(vaults[0]), VaultType.E4626);
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

    function testEsX128Default() public view {
        uint256[MAX_TOKENS] memory esX128 = simplexFacet.getEsX128();
        for (uint256 i = 0; i < MAX_TOKENS; i++) {
            assertEq(esX128[i], 10 << 128);
        }
    }

    function testGetEX128Default() public view {
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

    function testGetAdjustorDefault() public view {
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

    // -- BGT exchanger tests ----

    function testGetBGTExchanger() public view {
        assertEq(simplexFacet.getBGTExchanger(), address(0x0));
    }

    function testSetBGTExchanger() public {
        vm.startPrank(owner);

        // set exchanger A
        address bgtExchangerA = makeAddr("bgtExchangerA");
        vm.expectEmit(true, true, true, true);
        emit SimplexFacet.BGTExchangerChanged(
            owner,
            address(0x0),
            bgtExchangerA
        );
        simplexFacet.setBGTExchanger(bgtExchangerA);

        // set exchanger B
        address bgtExchangerB = makeAddr("bgtExchangerB");
        vm.expectEmit(true, true, true, true);
        emit SimplexFacet.BGTExchangerChanged(
            owner,
            bgtExchangerA,
            bgtExchangerB
        );
        simplexFacet.setBGTExchanger(bgtExchangerB);

        vm.stopPrank();
    }

    function testRevertBGTExchangerIsZeroAddress() public {
        vm.startPrank(owner);

        vm.expectRevert(SimplexFacet.BGTExchangerIsZeroAddress.selector);
        simplexFacet.setBGTExchanger(address(0x0));

        vm.stopPrank();
    }

    function testRevertSetBGTExchangerNotOwner() public {
        address bgtExchanger = makeAddr("bgtExchanger");
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.setBGTExchanger(bgtExchanger);
    }

    // -- initTarget tests ----

    function testGetInitTarget() public view {
        assertEq(simplexFacet.getInitTarget(), SimplexLib.DEFAULT_INIT_TARGET);
    }

    function testSetInitTarget() public {
        vm.startPrank(owner);

        // set init target 1e6
        vm.expectEmit(true, false, false, true);
        emit SimplexFacet.InitTargetChanged(
            owner,
            SimplexLib.DEFAULT_INIT_TARGET,
            1e6
        );
        simplexFacet.setInitTarget(1e6);

        // set init target 0
        vm.expectEmit(true, false, false, true);
        emit SimplexFacet.InitTargetChanged(owner, 1e6, 0);
        simplexFacet.setInitTarget(0);

        // set init target 1e18
        vm.expectEmit(true, false, false, true);
        emit SimplexFacet.InitTargetChanged(owner, 0, 1e18);
        simplexFacet.setInitTarget(1e18);

        vm.stopPrank();
    }

    function testRevertSetInitTargetNotOwner() public {
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.setInitTarget(1e6);
    }

    // -- searchParams tests ----

    function testGetSearchParams() public view {
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

    // -- getNumVertices tests ----

    function testGetNumVertices() public view {
        assertEq(simplexFacet.getNumVertices(), tokens.length);
    }

    function testGetTokens() public view {
        address[] memory _tokens = simplexFacet.getTokens();
        for (uint8 i = 0; i < tokens.length; ++i) {
            assertEq(_tokens[i], tokens[i]);
        }
    }
}

contract SimplexFacetVertexTest is MultiSetupTest {
    MockERC20[] public mockTokens;
    MockERC4626[] public mockVaults;

    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        vm.stopPrank();

        mockTokens.push(new MockERC20("Test Token 0", "TEST0", 18));
        mockTokens.push(new MockERC20("Test Token 1", "TEST1", 18));

        mockVaults.push(new MockERC4626(token0, "Mock Vault 0", "MVLT0"));
        mockVaults.push(new MockERC4626(token1, "Mock Vault 1", "MVLT1"));
    }

    function testAddVertex() public {
        vm.startPrank(owner);

        // Add first vertex
        simplexFacet.addVertex(
            address(mockTokens[0]),
            address(mockVaults[0]),
            VaultType.E4626
        );

        // Add second vertex
        simplexFacet.addVertex(
            address(mockTokens[1]),
            address(mockVaults[1]),
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
            address(mockTokens[0]),
            address(0),
            VaultType.UnImplemented
        );

        // Add second vertex
        vm.expectRevert(
            abi.encodeWithSelector(VaultLib.VaultTypeNotRecognized.selector, 0)
        );
        simplexFacet.addVertex(
            address(mockTokens[1]),
            address(0),
            VaultType.UnImplemented
        );

        vm.stopPrank();
    }

    function testAddVertexRevertNonOwner() public {
        vm.startPrank(alice);

        vm.expectRevert();
        simplexFacet.addVertex(
            address(mockTokens[0]),
            address(mockVaults[0]),
            VaultType.E4626
        );

        vm.stopPrank();
    }

    function testAddVertexRevertsForDuplicate() public {
        vm.startPrank(owner);

        // Add vertex first time
        simplexFacet.addVertex(
            address(mockTokens[0]),
            address(mockVaults[0]),
            VaultType.E4626
        );

        // Try to add same vertex again
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenRegLib.TokenAlreadyRegistered.selector,
                address(mockTokens[0])
            )
        ); // Should revert for duplicate vertex
        simplexFacet.addVertex(
            address(mockTokens[0]),
            address(mockVaults[0]),
            VaultType.E4626
        );

        vm.stopPrank();
    }
}

contract SimplexFacetClosureTest is MultiSetupTest {
    uint128 public constant INITT = SimplexLib.DEFAULT_INIT_TARGET;

    function setUp() public {
        _newDiamond();
        _newTokens(8);
        _fundAccount(address(this));
    }

    function testAddClosure() public {
        uint16 cid = 0x1 + 0x24 + 0x64;
        simplexFacet.addClosure(cid, INITT, 1 << 123, 1 << 125);
        (
            uint256 baseFeeX128,
            uint256 protocolTakeX128,
            uint256[MAX_TOKENS] memory earningsPerValueX128,
            uint256 bgtPerBgtValueX128,
            uint256[MAX_TOKENS] memory unexchangedPerBgtValueX128
        ) = simplexFacet.getClosureFees(cid);
        assertEq(baseFeeX128, 1 << 123);
        assertEq(protocolTakeX128, 1 << 125);
        assertEq(bgtPerBgtValueX128, 0);
        for (uint256 i = 0; i < MAX_TOKENS; ++i) {
            assertEq(earningsPerValueX128[i], 0);
            assertEq(unexchangedPerBgtValueX128[i], 0);
        }

        // Try adding a single token closure which is possible!
        simplexFacet.addClosure(0x32, INITT, 123 << 120, 81 << 121);
    }

    function testAddClosureWithNonExistentToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Store.UninitializedVertex.selector,
                VertexLib.newId(9)
            )
        );
        simplexFacet.addClosure(1 + (1 << 9), INITT, 1 << 124, 1 << 124);
    }

    function testAddClosureTargetTooSmall() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SimplexFacet.InsufficientStartingTarget.selector,
                INITT - 1
            )
        );
        simplexFacet.addClosure(1 + (1 << 8), INITT - 1, 1 << 124, 1 << 124);
    }

    function testGetNonExistentClosure() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Store.UninitializedClosure.selector,
                ClosureId.wrap(0x7)
            )
        );
        simplexFacet.getClosure(0x7);
    }

    function testGetEmptyClosure() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Store.EmptyClosure.selector,
                ClosureId.wrap(0)
            )
        );
        simplexFacet.getClosure(0x0);

        vm.expectRevert();
        simplexFacet.addClosure(0x0, INITT, 1 << 124, 1 << 124);
    }
}
