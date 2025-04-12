// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";

import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {Store} from "../../src/multi/Store.sol";
import {TokenRegistry, TokenRegistryImpl} from "../../src/multi/Token.sol";

contract TokenTest is Test {
    // -- register tests ----

    function testRegister() public {
        TokenRegistry storage tokenReg = Store.tokenRegistry();

        // register token 1
        vm.expectEmit(true, false, false, true);
        emit TokenRegistryImpl.TokenRegistered(address(0x1));
        tokenReg.register(address(0x1));

        assertEq(tokenReg.tokens.length, 1);
        assertEq(tokenReg.tokenIdx[address(0x1)], 0);

        // register token 2
        vm.expectEmit(true, false, false, true);
        emit TokenRegistryImpl.TokenRegistered(address(0x2));
        tokenReg.register(address(0x2));

        assertEq(tokenReg.tokens.length, 2);
        assertEq(tokenReg.tokenIdx[address(0x2)], 1);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertRegisterAtTokenCapacity() public {
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        for (uint160 i = 0; i < MAX_TOKENS; i++) {
            tokenReg.register(address(i));
        }

        vm.expectRevert(
            abi.encodeWithSelector(TokenRegistryImpl.AtTokenCapacity.selector)
        );
        tokenReg.register(address(uint160(MAX_TOKENS)));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertRegisterTokenAlreadyRegistered() public {
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        tokenReg.register(address(0x1));

        vm.expectRevert(
            abi.encodeWithSelector(
                TokenRegistryImpl.TokenAlreadyRegistered.selector,
                address(0x1)
            )
        );
        tokenReg.register(address(0x1));
    }

    // -- numVertices tests ----

    function testNumVertices() public {
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        assertEq(tokenReg.numVertices(), 0);

        for (uint160 i = 1; i <= MAX_TOKENS; i++) {
            tokenReg.register(address(i));
            assertEq(tokenReg.numVertices(), i);
        }
    }

    // -- getIdx tests ----

    function testGetIdx() public {
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        tokenReg.register(address(0x1));
        tokenReg.register(address(0x2));
        tokenReg.register(address(0x3));

        assertEq(tokenReg.getIdx(address(0x1)), 0);
        assertEq(tokenReg.getIdx(address(0x2)), 1);
        assertEq(tokenReg.getIdx(address(0x3)), 2);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertGetIdxTokenNotFound() public {
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenRegistryImpl.TokenNotFound.selector,
                address(0x1)
            )
        );
        tokenReg.getIdx(address(0x1));
    }

    // -- getToken tests ----

    function testGetToken() public {
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        tokenReg.register(address(0x1));
        tokenReg.register(address(0x2));
        tokenReg.register(address(0x3));

        assertEq(tokenReg.getToken(0), address(0x1));
        assertEq(tokenReg.getToken(1), address(0x2));
        assertEq(tokenReg.getToken(2), address(0x3));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertGetTokenIndexNotFound() public {
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        tokenReg.register(address(0x1));
        tokenReg.register(address(0x2));
        tokenReg.register(address(0x3));

        vm.expectRevert(
            abi.encodeWithSelector(TokenRegistryImpl.IndexNotFound.selector, 3)
        );
        tokenReg.getToken(3);
    }

    // -- isRegistered tests ----

    function testIsRegistered() public {
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        assertFalse(tokenReg.isRegistered(address(0x1)));
        assertFalse(tokenReg.isRegistered(address(0x2)));
        assertFalse(tokenReg.isRegistered(address(0x3)));

        tokenReg.register(address(0x1));
        assertTrue(tokenReg.isRegistered(address(0x1)));
        assertFalse(tokenReg.isRegistered(address(0x2)));

        tokenReg.register(address(0x2));
        assertTrue(tokenReg.isRegistered(address(0x1)));
        assertTrue(tokenReg.isRegistered(address(0x2)));
        assertFalse(tokenReg.isRegistered(address(0x3)));
    }
}
