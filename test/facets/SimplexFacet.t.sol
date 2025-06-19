// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";

import {AdminLib} from "Commons/Util/Admin.sol";

import {IAdjustor} from "../../src/integrations/adjustor/IAdjustor.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {MultiSetupTest} from "./MultiSetup.u.sol";
import {SearchParams} from "../../src/multi/Value.sol";
import {SimplexAdminFacet, SimplexSetFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {Simplex, SimplexLib} from "../../src/multi/Simplex.sol";
import {Store} from "../../src/multi/Store.sol";
import {TokenRegLib} from "../../src/multi/Token.sol";
import {NullAdjustor} from "../../src/integrations/adjustor/NullAdjustor.sol";
import {VaultType, VaultLib} from "../../src/multi/vertex/VaultProxy.sol";
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
        _newTokens(4);
        _initializeClosure(0x7);
        _initializeClosure(0x3);
        vm.stopPrank();
    }

    // -- addClosure tests ----

    function testAddClosureSingleVertex() public {
        vm.startPrank(owner);

        IERC20 token = IERC20(tokens[0]);

        uint128 startingTarget = 2e18;
        uint128 baseFeeX128 = 1e10;
        uint128 protocolTakeX128 = 1e6;
        simplexFacet.setSimplexFees(baseFeeX128, protocolTakeX128);

        // deal owner required tokens and approve transfer
        deal(tokens[0], owner, startingTarget);
        IERC20(token).approve(address(diamond), startingTarget);

        // balances before
        uint256 balanceOwner = token.balanceOf(owner);
        uint256 balanceVault = token.balanceOf(address(vaults[0]));

        // check the owner transfers to the diamond before sending to the vault
        vm.expectCall(
            address(token),
            abi.encodeCall(token.transferFrom, (owner, diamond, startingTarget))
        );

        // add closure
        simplexFacet.addClosure(0x1, startingTarget);

        // check balances
        assertEq(token.balanceOf(owner), balanceOwner - startingTarget);
        assertEq(
            token.balanceOf(address(vaults[0])),
            balanceVault + startingTarget
        );

        // check closure
        (
            uint8 n,
            uint256 targetX128,
            uint256[MAX_TOKENS] memory balances,
            uint256 valueStaked,
            uint256 bgtValueStaked
        ) = simplexFacet.getClosureValue(0x1);
        assertEq(n, 1);
        assertEq(targetX128, uint256(startingTarget) << 128);
        assertEq(balances[0], startingTarget);
        assertEq(valueStaked, startingTarget);
        assertEq(bgtValueStaked, 0);

        vm.stopPrank();
    }

    function testAddClosureMultiVertexDifferentToRealValues() public {
        vm.startPrank(owner);

        IERC20 token0 = IERC20(tokens[0]);

        // Add a 6 decimal token.
        IERC20 usdc = new MockERC20("Test Token", "T", 6);
        IERC4626 usdcVault = IERC4626(
            address(new MockERC4626(ERC20(address(usdc)), "vault T", "VT"))
        );
        uint8 tokenIdx = uint8(tokens.length);
        tokens.push(address(usdc));
        vaults.push(usdcVault);

        // verify assumptions about setup
        assertEq(tokens.length, tokenIdx + 1);
        assertEq(vaults.length, tokenIdx + 1);

        simplexFacet.addVertex(
            address(usdc),
            address(usdcVault),
            VaultType.E4626
        );

        uint16 closureId = 0x1 | uint16(1 << tokenIdx); // 0th and last token
        uint128 startingTarget = 100e24;
        uint128 baseFeeX128 = 1e10;
        uint128 protocolTakeX128 = 1e6;
        simplexFacet.setSimplexFees(baseFeeX128, protocolTakeX128);

        // deal owner required tokens and approve transfer
        // notice usdc has different real requirements due to the result of the adjustor
        deal(address(token0), owner, 100e24);
        deal(address(usdc), owner, 100e12);
        token0.approve(address(diamond), 100e24);
        usdc.approve(address(diamond), 100e12);

        // balances before
        uint256 balanceOwner0 = token0.balanceOf(owner);
        uint256 balanceOwnerUSDC = usdc.balanceOf(owner);
        uint256 balanceVault0 = token0.balanceOf(address(vaults[0]));
        uint256 balanceVaultUSDC = usdc.balanceOf(address(usdcVault));

        // check the owner transfers to the diamond before sending to the vault
        vm.expectCall(
            address(token0),
            abi.encodeCall(token0.transferFrom, (owner, diamond, 100e24))
        );
        vm.expectCall(
            address(usdc),
            abi.encodeCall(usdc.transferFrom, (owner, diamond, 100e12))
        );

        // add closure
        simplexFacet.addClosure(closureId, startingTarget);

        // check balances
        assertEq(token0.balanceOf(owner), balanceOwner0 - 100e24);
        assertEq(usdc.balanceOf(owner), balanceOwnerUSDC - 100e12);
        assertEq(token0.balanceOf(address(vaults[0])), balanceVault0 + 100e24);
        assertEq(usdc.balanceOf(address(usdcVault)), balanceVaultUSDC + 100e12);

        // check closure
        (
            uint8 n,
            uint256 targetX128,
            uint256[MAX_TOKENS] memory balances,
            uint256 valueStaked,
            uint256 bgtValueStaked
        ) = simplexFacet.getClosureValue(closureId);
        assertEq(n, 2);
        assertEq(targetX128, uint256(startingTarget) << 128);
        assertEq(balances[0], 100e24);
        assertEq(balances[tokenIdx], 100e24);
        assertEq(valueStaked, 200e24);
        assertEq(bgtValueStaked, 0);

        vm.stopPrank();
    }

    function testRevertAddClosureInsufficientStartingTarget() public {
        vm.startPrank(owner);

        vm.expectRevert(
            abi.encodeWithSelector(
                SimplexAdminFacet.InsufficientStartingTarget.selector,
                1e6,
                SimplexLib.DEFAULT_INIT_TARGET
            )
        );
        simplexFacet.addClosure(0x1, 1e6);

        vm.stopPrank();
    }

    function testRevertAddClosureNotOwner() public {
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.addClosure(0x1, 1e8);
    }

    // -- addVertex tests ----

    function testAddVertex() public {
        vm.startPrank(owner);

        // vertex A params
        address tokenA = address(new MockERC20("tokenA", "A", 18));
        address vaultA = makeAddr("vaultA");
        VertexId vidA = VertexLib.newId(uint8(tokens.length));

        // add vertex A
        vm.expectEmit(true, true, false, true);
        emit SimplexAdminFacet.VertexAdded(
            tokenA,
            vaultA,
            vidA,
            VaultType.E4626
        );
        simplexFacet.addVertex(tokenA, vaultA, VaultType.E4626);

        // check vertex A
        Vertex memory vertexA = storeManipulatorFacet.getVertex(vidA);
        assertEq(VertexId.unwrap(vertexA.vid), VertexId.unwrap(vidA));
        assertEq(vertexA._isLocked, false);

        // check vault A
        (address activeVaultA, address backupVaultA) = vaultFacet.viewVaults(
            tokenA
        );
        assertEq(activeVaultA, vaultA);
        assertEq(backupVaultA, address(0x0));

        // vertex B params
        address tokenB = address(new MockERC20("tokenB", "B", 18));
        address vaultB = makeAddr("vaultB");
        VertexId vidB = VertexLib.newId(uint8(tokens.length + 1));

        // add vertex B
        vm.expectEmit(true, true, false, true);
        emit SimplexAdminFacet.VertexAdded(
            tokenB,
            vaultB,
            vidB,
            VaultType.E4626
        );
        simplexFacet.addVertex(tokenB, vaultB, VaultType.E4626);

        // check vertex A
        Vertex memory vertexB = storeManipulatorFacet.getVertex(vidB);
        assertEq(VertexId.unwrap(vertexB.vid), VertexId.unwrap(vidB));
        assertEq(vertexB._isLocked, false);

        // check vault A
        (address activeVaultB, address backupVaultB) = vaultFacet.viewVaults(
            tokenB
        );
        assertEq(activeVaultB, vaultB);
        assertEq(backupVaultB, address(0x0));

        vm.stopPrank();
    }

    function testRevertAddVertexVaultTypeNotRecognized() public {
        vm.startPrank(owner);

        address token = address(new MockERC20("token", "t", 18));
        address vault = makeAddr("vault");

        vm.expectRevert(
            abi.encodeWithSelector(VaultLib.VaultTypeNotRecognized.selector, 0)
        );
        simplexFacet.addVertex(token, vault, VaultType.UnImplemented);

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
        uint256 originalVaultBalance = token.balanceOf(address(vaults[0]));

        uint256[MAX_TOKENS] memory protocolEarnings;
        protocolEarnings[0] = 7e18;
        // Deposits into the reserve.
        storeManipulatorFacet.setProtocolEarnings(protocolEarnings);

        // record balances
        uint256 ownerBalance = token.balanceOf(owner);
        uint256 protocolBalance = token.balanceOf(diamond);
        uint256 vaultBalance = token.balanceOf(address(vaults[0]));
        assertEq(protocolBalance, 1e18); // only 1e18 of donations left.
        assertEq(vaultBalance, originalVaultBalance + 7e18); // Protocol earnings are in reserve vault.

        // withdraw
        vm.expectEmit(true, false, false, true);
        emit SimplexAdminFacet.ProtocolFeesWithdrawn(
            address(token),
            8e18,
            7e18
        );
        simplexFacet.withdraw(address(token));

        // check balances
        assertEq(token.balanceOf(owner), ownerBalance + 8e18);
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
        uint256 originalVaultBalance = token.balanceOf(address(vaults[0]));

        uint256[MAX_TOKENS] memory protocolEarnings;
        protocolEarnings[0] = 7e18;
        // Deposits into the reserve.
        storeManipulatorFacet.setProtocolEarnings(protocolEarnings);

        // record balances
        uint256 ownerBalance = token.balanceOf(owner);
        uint256 protocolBalance = token.balanceOf(diamond);
        uint256 vaultBalance = token.balanceOf(address(vaults[0]));
        assertGe(protocolBalance, 0);
        assertEq(vaultBalance, originalVaultBalance + 7e18); // Protocol earnings are in reserve vault.

        // withdraw
        vm.expectEmit(true, false, false, true);
        emit SimplexAdminFacet.ProtocolFeesWithdrawn(
            address(token),
            7e18,
            7e18
        );
        simplexFacet.withdraw(address(token));

        // check balances
        assertEq(token.balanceOf(owner), ownerBalance + 7e18);
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
        emit SimplexAdminFacet.ProtocolFeesWithdrawn(address(token), 1e18, 0);
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

    /// Change E for a token that doesn't have closures yet
    function testUnregisteredSetEX128() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, false, true);
        emit SimplexSetFacet.EfficiencyFactorChanged(
            owner,
            tokens[3],
            10 << 128,
            20 << 128
        );
        simplexFacet.setEX128(tokens[3], 20 << 128, 0);

        uint256 esX128 = simplexFacet.getEX128(tokens[3]);
        assertEq(esX128, 20 << 128);

        // Doesn't require any token transfers because no closures are registered.
        simplexFacet.setEX128(tokens[3], 10 << 128, 0);

        vm.stopPrank();
    }

    /// Change E for a token that has closures and the LP balances are moved to fees.
    function testRegisteredSetEX128Increase() public {
        _fundAccount(address(this));
        uint256[MAX_TOKENS] memory limits;
        // Add liquidity to track.
        valueFacet.addValue(address(this), 0x3, 1e22, 0, limits);
        // Swap a bit so tokens aren't balanced.
        swapFacet.swap(address(this), tokens[0], tokens[1], 1.78e20, 0, 0x3);

        // raising E will move LP deposits into fees.
        // Vault balance should not change.
        uint256 preBalance = ERC20(tokens[0]).balanceOf(address(vaults[0]));
        (
            ,
            uint256 preTarget,
            uint256[MAX_TOKENS] memory preBalances,
            ,

        ) = simplexFacet.getClosureValue(0x3);
        (uint256[MAX_TOKENS] memory preEarningsPerValueX128, , ) = simplexFacet
            .getClosureFees(0x3);
        (
            uint256 preValue,
            ,
            uint256[MAX_TOKENS] memory preEarnings,

        ) = valueFacet.queryValue(address(this), 0x3);

        vm.expectEmit(true, true, false, true);
        emit SimplexSetFacet.EfficiencyFactorChanged(
            owner,
            tokens[0],
            10 << 128,
            20 << 128
        );
        vm.prank(owner);
        simplexFacet.setEX128(tokens[0], 20 << 128, 0);

        {
            uint256 postBalance = ERC20(tokens[0]).balanceOf(
                address(vaults[0])
            );
            assertEq(postBalance, preBalance, "b=");
        }
        {
            (
                ,
                uint256 postTarget,
                uint256[MAX_TOKENS] memory postBalances,
                ,

            ) = simplexFacet.getClosureValue(0x3);
            assertEq(preTarget, postTarget, "t=");
            assertLt(postBalances[0], preBalances[0], "bp<");
        }
        {
            (
                uint256[MAX_TOKENS] memory postEarningsPerValueX128,
                ,

            ) = simplexFacet.getClosureFees(0x3);
            assertGt(
                postEarningsPerValueX128[0],
                preEarningsPerValueX128[0],
                "fe>"
            );
        }
        {
            uint256 postValue;
            uint256[MAX_TOKENS] memory postEarnings;

            (postValue, , postEarnings, ) = valueFacet.queryValue(
                address(this),
                0x3
            );
            assertEq(postValue, preValue, "v=");
            assertGt(postEarnings[0], preEarnings[0], "qpe>");
        }
    }

    /// Change E for a token that has closures and we'll have to transfer in tokens.
    function testRegisteredSetEX128Decrease() public {
        _fundAccount(address(this));
        uint256[MAX_TOKENS] memory limits;
        // Add liquidity to track.
        valueFacet.addValue(address(this), 0x3, 1e22, 0, limits);
        // Swap a bit so tokens aren't balanced.
        swapFacet.swap(address(this), tokens[0], tokens[1], 1.78e20, 0, 0x3);

        // decreasing E will require more tokens to be deposited.
        // Vault balance will increase.
        uint256 preBalance = ERC20(tokens[0]).balanceOf(address(vaults[0]));
        (
            ,
            uint256 preTarget,
            uint256[MAX_TOKENS] memory preBalances,
            ,

        ) = simplexFacet.getClosureValue(0x3);
        (uint256[MAX_TOKENS] memory preEarningsPerValueX128, , ) = simplexFacet
            .getClosureFees(0x3);
        (
            uint256 preValue,
            ,
            uint256[MAX_TOKENS] memory preEarnings,

        ) = valueFacet.queryValue(address(this), 0x3);

        // We need tokens to send.
        vm.expectRevert();
        vm.prank(owner);
        simplexFacet.setEX128(tokens[0], 5 << 128, type(uint256).max);

        _fundAccount(owner);

        // We need to send more than alotted.
        vm.expectRevert(
            abi.encodeWithSelector(
                SimplexSetFacet.SetESlippageExceeded.selector,
                2388393271069068,
                1e15
            )
        );
        vm.prank(owner);
        simplexFacet.setEX128(tokens[0], 5 << 128, 1e15);

        vm.expectEmit(true, true, false, true);
        emit SimplexSetFacet.EfficiencyFactorChanged(
            owner,
            tokens[0],
            10 << 128,
            5 << 128
        );
        vm.prank(owner);
        simplexFacet.setEX128(tokens[0], 5 << 128, 100e18);

        {
            uint256 postBalance = ERC20(tokens[0]).balanceOf(
                address(vaults[0])
            );
            assertGt(postBalance, preBalance, "b>");
        }
        {
            (
                ,
                uint256 postTarget,
                uint256[MAX_TOKENS] memory postBalances,
                ,

            ) = simplexFacet.getClosureValue(0x3);
            assertEq(preTarget, postTarget, "t=");
            assertGt(postBalances[0], preBalances[0], "bp>");
        }
        {
            (
                uint256[MAX_TOKENS] memory postEarningsPerValueX128,
                ,

            ) = simplexFacet.getClosureFees(0x3);
            assertEq(
                postEarningsPerValueX128[0],
                preEarningsPerValueX128[0],
                "fe="
            );
        }
        {
            uint256 postValue;
            uint256[MAX_TOKENS] memory postEarnings;

            (postValue, , postEarnings, ) = valueFacet.queryValue(
                address(this),
                0x3
            );
            assertEq(postValue, preValue, "v=");
            assertEq(postEarnings[0], preEarnings[0], "qpe=");
        }
    }

    function testRevertSetEX128NotOwner() public {
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.setEX128(tokens[0], 1, type(uint256).max);
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
        emit SimplexSetFacet.AdjustorChanged(
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
        emit SimplexSetFacet.AdjustorChanged(owner, adjustorA, adjustorB);

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
        emit SimplexSetFacet.BGTExchangerChanged(
            owner,
            address(0x0),
            bgtExchangerA
        );
        simplexFacet.setBGTExchanger(bgtExchangerA);

        // set exchanger B
        address bgtExchangerB = makeAddr("bgtExchangerB");
        vm.expectEmit(true, true, true, true);
        emit SimplexSetFacet.BGTExchangerChanged(
            owner,
            bgtExchangerA,
            bgtExchangerB
        );
        simplexFacet.setBGTExchanger(bgtExchangerB);

        vm.stopPrank();
    }

    function testRevertBGTExchangerIsZeroAddress() public {
        vm.startPrank(owner);

        vm.expectRevert(SimplexSetFacet.BGTExchangerIsZeroAddress.selector);
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
        emit SimplexSetFacet.InitTargetChanged(
            owner,
            SimplexLib.DEFAULT_INIT_TARGET,
            1e6
        );
        simplexFacet.setInitTarget(1e6);

        // set init target 0
        vm.expectEmit(true, false, false, true);
        emit SimplexSetFacet.InitTargetChanged(owner, 1e6, 0);
        simplexFacet.setInitTarget(0);

        // set init target 1e18
        vm.expectEmit(true, false, false, true);
        emit SimplexSetFacet.InitTargetChanged(owner, 0, 1e18);
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
        emit SimplexSetFacet.SearchParamsChanged(
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
                SimplexSetFacet.NonPositiveDeMinimusX128.selector,
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
                SimplexSetFacet.NonPositiveDeMinimusX128.selector,
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

    // getTokens tests ----

    function testGetTokens() public view {
        address[] memory _tokens = simplexFacet.getTokens();
        for (uint8 i = 0; i < tokens.length; ++i) {
            assertEq(_tokens[i], tokens[i]);
        }
    }

    // -- getNumVertices tests ----

    function testGetNumVertices() public view {
        assertEq(simplexFacet.getNumVertices(), tokens.length);
    }

    // -- getIdx tests ----

    function testGetIdx() public view {
        assertEq(simplexFacet.getIdx(tokens[0]), 0);
        assertEq(simplexFacet.getIdx(tokens[1]), 1);
        assertEq(simplexFacet.getIdx(tokens[2]), 2);
    }

    function testRevertGetIdxTokenNotFound() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenRegLib.TokenNotFound.selector,
                address(0xA)
            )
        );
        simplexFacet.getIdx(address(0xA));
    }

    // -- getVertexId ----

    function testGetVertexId() public view {
        assertEq(simplexFacet.getVertexId(tokens[0]), 1 << 8);
        assertEq(simplexFacet.getVertexId(tokens[1]), (1 << 9) + 1);
        assertEq(simplexFacet.getVertexId(tokens[2]), (1 << 10) + 2);
    }

    function testRevertGetVertexIdTokenNotFound() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenRegLib.TokenNotFound.selector,
                address(0xA)
            )
        );
        simplexFacet.getVertexId(address(0xA));
    }

    // -- name tests ----

    function testSetName() public {
        vm.startPrank(owner);

        vm.expectEmit(false, false, false, true);
        emit SimplexSetFacet.NewName("name", "symbol");
        simplexFacet.setName("name", "symbol");

        (string memory name, string memory symbol) = simplexFacet.getName();
        assertEq(name, "name");
        assertEq(symbol, "symbol");

        vm.stopPrank();
    }

    function testRevertSetNameNotOwner() public {
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.setName("name", "symbol");
    }

    // -- getClosureValue tests ----

    function testGetClosureValueDefault() public view {
        (
            uint8 n,
            uint256 targetX128,
            uint256[MAX_TOKENS] memory balances,
            uint256 valueStaked,
            uint256 bgtValueStaked
        ) = simplexFacet.getClosureValue(0x7);
        assertEq(n, 3);
        assertEq(targetX128, uint256(INITIAL_VALUE) << 128);
        assertEq(valueStaked, INITIAL_VALUE * 3);
        assertEq(bgtValueStaked, 0);
        for (uint8 i = 0; i < 3; ++i) {
            assertEq(balances[i], INITIAL_VALUE);
        }
        for (uint8 i = 3; i < MAX_TOKENS; ++i) {
            assertEq(balances[i], 0);
        }
    }

    function testGetClosureValue() public {
        uint16 closureId = 0x7;

        // overwrite closure in storage
        uint8 _n = 4;
        uint256 _targetX128 = 50;
        uint256[MAX_TOKENS] memory _balances;
        _balances[0] = 10e18;
        _balances[1] = 2e18;
        uint256 _valueStaked = 20;
        uint256 _bgtValueStaked = 40;

        storeManipulatorFacet.setClosureValue(
            closureId,
            _n,
            _targetX128,
            _balances,
            _valueStaked,
            _bgtValueStaked
        );

        // get closure value
        (
            uint8 n,
            uint256 targetX128,
            uint256[MAX_TOKENS] memory balances,
            uint256 valueStaked,
            uint256 bgtValueStaked
        ) = simplexFacet.getClosureValue(0x7);

        // check value
        assertEq(_n, n);
        assertEq(_targetX128, targetX128);
        assertEq(_valueStaked, valueStaked);
        assertEq(_bgtValueStaked, bgtValueStaked);
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            assertEq(_balances[i], balances[i]);
        }
    }

    function testRevertGetClosureValueUninitializedClosure() public {
        vm.expectRevert(
            abi.encodeWithSelector(Store.UninitializedClosure.selector, 0x1999)
        );
        simplexFacet.getClosureValue(0x1999);
    }

    // -- closureFees tests ----

    function testGetClosureFeesDefault() public view {
        (uint256 baseFeeX128, uint256 protocolTakeX128) = simplexFacet
            .getSimplexFees();

        (
            uint256[MAX_TOKENS] memory earningsPerValueX128,
            uint256 bgtPerBgtValueX128,
            uint256[MAX_TOKENS] memory unexchangedPerBgtValueX128
        ) = simplexFacet.getClosureFees(0x7);

        // check fees
        assertEq(baseFeeX128, 0);
        assertEq(protocolTakeX128, 0);
        assertEq(bgtPerBgtValueX128, 0);
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            assertEq(earningsPerValueX128[i], 0);
            assertEq(unexchangedPerBgtValueX128[i], 0);
        }
    }

    function testGetClosureFees() public {
        uint16 closureId = 0x7;

        // overwrite closure in storage
        uint128 _baseFeeX128 = 1;
        uint128 _protocolTakeX128 = 2;
        uint256[MAX_TOKENS] memory _earningsPerValueX128;
        uint256 _bgtPerBgtValueX128 = 3;
        uint256[MAX_TOKENS] memory _unexchangedPerBgtValueX128;
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            _earningsPerValueX128[i] = 10e8 + i;
            _unexchangedPerBgtValueX128[i] = 20e8 + i;
        }

        storeManipulatorFacet.setClosureFees(
            closureId,
            _baseFeeX128,
            _protocolTakeX128,
            _earningsPerValueX128,
            _bgtPerBgtValueX128,
            _unexchangedPerBgtValueX128
        );

        // get closure fees
        (uint256 baseFeeX128, uint256 protocolTakeX128) = simplexFacet
            .getSimplexFees();
        (
            uint256[MAX_TOKENS] memory earningsPerValueX128,
            uint256 bgtPerBgtValueX128,
            uint256[MAX_TOKENS] memory unexchangedPerBgtValueX128
        ) = simplexFacet.getClosureFees(0x7);

        // check fees
        assertEq(_baseFeeX128, baseFeeX128);
        assertEq(_protocolTakeX128, protocolTakeX128);
        assertEq(_bgtPerBgtValueX128, bgtPerBgtValueX128);
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            assertEq(_earningsPerValueX128[i], earningsPerValueX128[i]);
            assertEq(
                _unexchangedPerBgtValueX128[i],
                unexchangedPerBgtValueX128[i]
            );
        }
    }

    function testRevertGetClosureFeesUninitializedClosure() public {
        vm.expectRevert(
            abi.encodeWithSelector(Store.UninitializedClosure.selector, 0x1999)
        );
        simplexFacet.getClosureFees(0x1999);
    }

    function testSetClosureFees() public {
        // set fees
        vm.startPrank(owner);
        simplexFacet.setSimplexFees(150, 250);
        vm.stopPrank();

        // get fees
        (uint256 baseFeeX128, uint256 protocolTakeX128) = simplexFacet
            .getSimplexFees();
        (
            uint256[MAX_TOKENS] memory earningsPerValueX128,
            uint256 bgtPerBgtValueX128,
            uint256[MAX_TOKENS] memory unexchangedPerBgtValueX128
        ) = simplexFacet.getClosureFees(0x7);

        // check fees
        assertEq(baseFeeX128, 150);
        assertEq(protocolTakeX128, 250);
        assertEq(bgtPerBgtValueX128, 0);
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            assertEq(earningsPerValueX128[i], 0);
            assertEq(unexchangedPerBgtValueX128[i], 0);
        }
    }

    function testRevertSetSimplexFeesNotOwner() public {
        vm.expectRevert(AdminLib.NotOwner.selector);
        simplexFacet.setSimplexFees(150, 250);
    }
}
