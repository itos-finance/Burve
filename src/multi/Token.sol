// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "./Storage.sol";

uint256 constant MAX_TOKENS = 16;

struct TokenRegistry {
    address[] tokens;
    mapping(address => uint8) tokenIdx;
}

using TokenRegistryImpl for TokenRegistrar global;

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
        if (self.tokenIdx[token] != 0 || self.tokens[0] == token)
            revert TokenAlreadyRegistered(token);
        idx = uint8(self.tokens.length);
        self.tokenIdx[token] = idx;
        self.tokens.push(token);
        // Init the vertex.
        Store.vertex(token).init(token);
        emit TokenRegistered(token);
    }

    /// We don't deregister tokens, but we can halt tokens through the vertex.
}

library TokenRegLib {
    function numVertices() internal view returns (uint8 n) {
        return uint8(Store().tokenReg().tokens.length);
    }

    function getIdx(address token) internal view returns (uint8 idx) {
        return Store().tokenReg().tokenIdx[token];
    }
}
