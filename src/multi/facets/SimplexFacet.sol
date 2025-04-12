// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {Vertex} from "../vertex/Vertex.sol";
import {VertexId, VertexLib} from "../vertex/Id.sol";
import {VaultType} from "../vertex/VaultProxy.sol";
import {AdminLib} from "Commons/Util/Admin.sol";
import {TokenRegistry, MAX_TOKENS} from "../Token.sol";
import {AdjustorLib} from "../Adjustor.sol";
import {ClosureId} from "../closure/Id.sol";
import {Closure} from "../closure/Closure.sol";
import {Simplex} from "../Simplex.sol";

contract SimplexFacet {
    event NewName(string newName, string symbol);
    event VertexAdded(
        address indexed token,
        address indexed vault,
        VertexId vid,
        VaultType vaultType
    );
    event FeesWithdrawn(address indexed token, uint256 amount);
    event DefaultEdgeSet(
        uint128 amplitude,
        int24 lowTick,
        int24 highTick,
        uint24 fee,
        uint8 feeProtocol
    );
    error InsufficientStartingTarget(uint128 startingTarget);

    /* Getters */
    /*
    /// TODO move to new view facet
    /// Convert your token of interest to the vertex id which you can
    /// sum with other vertex ids to create a closure Id.
    function getVertexId(address token) external view returns (uint16 vid) {
        return VertexId.unwrap(newVertexId(token));
    }

    /// TODO move to new view facet
    /// Fetch the list of tokens registered in this simplex.
    function getTokens() external view returns (address[] memory tokens) {
        address[] storage _t = Store.tokenRegistry().tokens;
        tokens = new address[](_t.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i] = _t[i];
        }
    }

    /// TODO move to new view facet
    /// Fetch the vertex index of the given token addresses.
    /// Returns a negative value if the token is not present.
    function getIndexes(
        address[] calldata tokens
    ) external view returns (int8[] memory idxs) {
        TokenRegistry storage reg = Store.tokenRegistry();
        idxs = new int8[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            idxs[i] = int8(reg.tokenIdx[tokens[i]]);
            if (idxs[i] == 0 && reg.tokens[0] != tokens[i]) {
                idxs[i] = -1;
            }
        }
    }

    /// TODO move to new view facet
    /// Get the number of currently installed vertices
    function numVertices() external view returns (uint8) {
        return TokenRegLib.numVertices();
    } */

    /* Admin Function */

    /// Add a token into this simplex.
    function addVertex(address token, address vault, VaultType vType) external {
        AdminLib.validateOwner();
        Store.tokenRegistry().register(token);
        Store.adjustor().cacheAdjustment(token);
        // We do this explicitly because a normal call to Store.vertex would validate the
        // vertex is already initialized which of course it is not yet.
        VertexId vid = VertexLib.newId(token);
        Vertex storage v = Store.load().vertices[vid];
        v.init(vid, token, vault, vType);
        emit VertexAdded(token, vault, vid, vType);
    }

    function addClosure(
        uint16 _cid,
        uint128 startingTarget,
        uint256 baseFeeX128,
        uint256 protocolTakeX128
    ) external {
        AdminLib.validateOwner();
        ClosureId cid = ClosureId.wrap(_cid);
        // We fetch the raw storage because Store.closure would check the closure for initialization.
        Closure storage c = Store.load().closures[cid];
        require(
            startingTarget >= Store.simplex().initTarget,
            InsufficientStartingTarget(startingTarget)
        );
        uint256[MAX_TOKENS] storage neededBalances = c.init(
            cid,
            startingTarget,
            baseFeeX128,
            protocolTakeX128
        );
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            if (!cid.contains(i)) continue;
            address token = tokenReg.tokens[i];
            uint256 realNeeded = AdjustorLib.toReal(
                token,
                neededBalances[i],
                true
            );
            TransferHelper.safeTransferFrom(
                token,
                msg.sender,
                address(this),
                realNeeded
            );
            Store.vertex(VertexLib.newId(i)).deposit(cid, realNeeded);
        }
    }

    /*     /// Withdraw fees earned by the protocol.
    function withdrawFees(address token, uint256 amount) external {
        AdminLib.validateOwner();
        // Normally tokens supporting the AMM ALWAYS resides in the vaults.
        // The only exception is
        // 1. When fees are earned by the protocol.
        // 2. When someone accidentally sends tokens to this address
        // 3. When someone donates.
        // Therefore we can just withdraw from this contract to resolve all three.
        TransferHelper.safeTransfer(token, msg.sender, amount);
        emit FeesWithdrawn(token, amount);
    }

    function setAdjustor(IAdjustor adj) external {
        AdminLib.validateOwner();
        Store.load().adjustor = adj;
        address[] storage tokens = Store.tokenRegistry().tokens;
        for (uint256 i = 0; i < tokens.length; ++i) {
            adj.cacheAdjustment(tokens[i]);
        }
    } */

    function setName(
        string calldata newName,
        string calldata newSymbol
    ) external {
        Simplex storage s = Store.simplex();
        s.name = newName;
        s.symbol = newSymbol;
        emit NewName(newName, newSymbol);
    }

    function getName()
        external
        view
        returns (string memory name, string memory symbol)
    {
        Simplex storage s = Store.simplex();
        name = s.name;
        symbol = s.symbol;
    }
}
