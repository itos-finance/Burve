// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ClosureId} from "../../src/multi/closure/Id.sol";
import {Closure} from "../../src/multi/closure/Closure.sol";
import {Store} from "../../src/multi/Store.sol";
import {Simplex, SimplexLib} from "../../src/multi/Simplex.sol";
import {ReserveLib} from "../../src/multi/vertex/Reserve.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {Vertex} from "../../src/multi/vertex/Vertex.sol";
import {VertexId, VertexLib} from "../../src/multi/vertex/Id.sol";

contract StoreManipulatorFacet {
    function setClosureValue(
        uint16 closureId,
        uint8 n,
        uint256 targetX128,
        uint256[MAX_TOKENS] memory balances,
        uint256 valueStaked,
        uint256 bgtValueStaked
    ) external {
        Closure storage c = Store.closure(ClosureId.wrap(closureId));
        c.n = n;
        c.targetX128 = targetX128;
        c.valueStaked = valueStaked;
        c.bgtValueStaked = bgtValueStaked;
        c.balances = balances;
    }

    function setClosureFees(
        uint16 closureId,
        uint128 defaultEdgeFeeX128,
        uint128 protocolTakeX128,
        uint256[MAX_TOKENS] memory earningsPerValueX128,
        uint256 bgtPerBgtValueX128,
        uint256[MAX_TOKENS] memory unexchangedPerBgtValueX128
    ) external {
        Closure storage c = Store.closure(ClosureId.wrap(closureId));
        Simplex storage s = Store.simplex();
        s.defaultEdgeFeeX128 = defaultEdgeFeeX128;
        s.protocolTakeX128 = protocolTakeX128;
        c.bgtPerBgtValueX128 = bgtPerBgtValueX128;
        c.earningsPerValueX128 = earningsPerValueX128;
        c.unexchangedPerBgtValueX128 = unexchangedPerBgtValueX128;
    }

    function setProtocolEarnings(
        uint256[MAX_TOKENS] memory _protocolEarnings
    ) external {
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            uint256 amount = _protocolEarnings[i];
            if (amount == 0) continue;
            uint256 shares = ReserveLib.deposit(VertexLib.newId(i), amount);
            SimplexLib.protocolTake(i, shares);
        }
    }

    function getVertex(VertexId vid) external view returns (Vertex memory v) {
        return Store.vertex(vid);
    }
}
