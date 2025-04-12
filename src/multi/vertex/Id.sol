// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MAX_TOKENS} from "./../Constants.sol";
import {Store} from "../Store.sol";
import {TokenRegistry} from "../Token.sol";

/// A vertex id is an uint where the bottom 8 bits is the idx, the next 16 bits
/// is a one-hot encoding of the idx.
type VertexId is uint24;

library VertexLib {
    function newId(uint8 idx) internal pure returns (VertexId) {
        // TODO: I'm confused about this calculation and don't know if it's correct
        return VertexId.wrap(uint24(1 << (idx + 8)) + idx);
    }

    function newId(address token) internal view returns (VertexId) {
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        uint8 idx = tokenReg.getIdx(token);
        // TODO: I'm confused about this calculation and don't know if it's correct
        return VertexId.wrap(uint24(1 << (idx + 8)) + idx);
    }

    function minId() internal pure returns (VertexId) {
        return newId(0);
    }
}

library VertexIdImpl {
    function isEq(VertexId self, VertexId other) internal pure returns (bool) {
        return VertexId.unwrap(self) == VertexId.unwrap(other);
    }

    function isNull(VertexId self) internal pure returns (bool) {
        return VertexId.unwrap(self) == 0;
    }

    function inc(VertexId self) internal pure returns (VertexId) {
        uint24 raw = VertexId.unwrap(self);
        return VertexId.wrap(((raw & 0xFFFF00) << 1) + ((raw & 0xFF) + 1));
    }

    function idx(VertexId self) internal pure returns (uint8) {
        return uint8(VertexId.unwrap(self));
    }

    function bit(VertexId self) internal pure returns (uint16) {
        return uint16(VertexId.unwrap(self) >> 8);
    }

    function isStop(VertexId self) internal pure returns (bool) {
        return uint8(VertexId.unwrap(self)) == MAX_TOKENS;
    }
}

using VertexIdImpl for VertexId global;
