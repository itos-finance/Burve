// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "./Store.sol";

uint256 constant MAX_TOKENS = 16;

struct TokenRegistry {
    address[] tokens;
    mapping(address => uint8) tokenIdx;
}

using TokenRegistryImpl for TokenRegistry global;

library TokenRegistryImpl {
    error AtTokenCapacity();
    error TokenNotFound(address token);
    error TokenAlreadyRegistered(address token);

    event TokenRegistered(address token);

    function register(
        TokenRegistry storage self,
        address token
    ) internal returns (uint8 idx) {
        if (self.tokens.length >= MAX_TOKENS) revert AtTokenCapacity();
        if (
            self.tokens.length > 0 &&
            (self.tokenIdx[token] != 0 || self.tokens[0] == token)
        ) revert TokenAlreadyRegistered(token);
        idx = uint8(self.tokens.length);
        self.tokenIdx[token] = idx;
        self.tokens.push(token);
        emit TokenRegistered(token);
    }

    /// We don't deregister tokens, but we can halt tokens through the vertex.
}

library TokenRegLib {
    error TokenNotFound(address);

    function numVertices() internal view returns (uint8 n) {
        return uint8(Store.tokenRegistry().tokens.length);
    }

    function getIdx(address token) internal view returns (uint8 idx) {
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        idx = tokenReg.tokenIdx[token];
        if (
            idx == 0 &&
            (tokenReg.tokens.length == 0 || tokenReg.tokens[0] != token)
        ) revert TokenNotFound(token);
    }

    function getToken(uint8 idx) internal view returns (address token) {
        return Store.tokenRegistry().tokens[idx];
    }
}
