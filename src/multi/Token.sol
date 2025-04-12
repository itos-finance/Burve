// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MAX_TOKENS} from "./Constants.sol";
import {Store} from "./Store.sol";

struct TokenRegistry {
    address[] tokens;
    mapping(address => uint8) tokenIdx;
}

using TokenRegistryImpl for TokenRegistry global;

library TokenRegistryImpl {
    /// Thrown when registering a token if the token registry is at capacity.
    error AtTokenCapacity();
    /// Thrown when registering a token if that token has already been registered.
    error TokenAlreadyRegistered(address token);
    /// Thrown during token address lookup if the token is not registered.
    error TokenNotFound(address token);
    /// Thrown during token index lookup if the index does not exist.
    error IndexNotFound(uint8 idx);

    /// Emitted when a new token is registered.
    event TokenRegistered(address token);

    /// @notice Registers a new token in the token registry.
    /// @dev Reverts if the token is already registered or if the registry is at capacity.
    /// @param self The token registry.
    /// @param token The address of the token to register.
    /// @return idx The index of the token in the registry.
    function register(
        TokenRegistry storage self,
        address token
    ) internal returns (uint8 idx) {
        if (self.tokens.length >= MAX_TOKENS) revert AtTokenCapacity();
        if (self.isRegistered(token)) revert TokenAlreadyRegistered(token);

        idx = uint8(self.tokens.length);
        self.tokenIdx[token] = idx;
        self.tokens.push(token);

        emit TokenRegistered(token);
    }

    /// @notice Returns the number of tokens in the registry.
    /// @param self The token registry.
    /// @return n The number of tokens in the registry.
    function numVertices(
        TokenRegistry storage self
    ) internal view returns (uint8 n) {
        return uint8(self.tokens.length);
    }

    /// @notice Returns the index of a token in the registry.
    /// @dev Reverts if the token is not registered.
    /// @param self The token registry.
    /// @param token The address of the token to look up.
    /// @return idx The index of the token in the registry.
    function getIdx(
        TokenRegistry storage self,
        address token
    ) internal view returns (uint8 idx) {
        if (!isRegistered(self, token)) revert TokenNotFound(token);
        idx = self.tokenIdx[token];
    }

    /// @notice Returns the address of a token at a given index in the registry.
    /// @dev Reverts if the index does not exist.
    /// @param self The token registry.
    /// @param idx The index of the token to look up.
    /// @return token The address of the token at the given index.
    function getToken(
        TokenRegistry storage self,
        uint8 idx
    ) internal view returns (address token) {
        if (idx >= self.tokens.length) revert IndexNotFound(idx);
        return self.tokens[idx];
    }

    /// @notice Checks if a token is registered in the registry.
    /// @param self The token registry.
    /// @param token The address of the token to check.
    function isRegistered(
        TokenRegistry storage self,
        address token
    ) internal view returns (bool) {
        return (self.tokens.length > 0 &&
            (self.tokenIdx[token] != 0 || self.tokens[0] == token));
    }
}
