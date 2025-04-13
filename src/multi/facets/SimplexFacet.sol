// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {AdminLib} from "Commons/Util/Admin.sol";
import {TokenRegLib, TokenRegistry, MAX_TOKENS} from "../Token.sol";
import {IAdjustor} from "../../integrations/adjustor/IAdjustor.sol";
import {AdjustorLib} from "../Adjustor.sol";
import {ClosureId} from "../closure/Id.sol";
import {Closure} from "../closure/Closure.sol";
import {SearchParams} from "../Value.sol";
import {Simplex, SimplexLib} from "../Simplex.sol";
import {Store} from "../Store.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {VaultType} from "../vertex/VaultProxy.sol";
import {Vertex} from "../vertex/Vertex.sol";
import {VertexId, VertexLib} from "../vertex/Id.sol";

contract SimplexFacet {
    error InsufficientStartingTarget(uint128 startingTarget);
    /// Throw when setting search params if deMinimusX128 is not positive.
    error NonPositiveDeMinimusX128(int256 deMinimusX128);

    event NewName(string newName, string symbol);
    event VertexAdded(
        address indexed token,
        address indexed vault,
        VertexId vid,
        VaultType vaultType
    );
    event FeesWithdrawn(address indexed token, uint256 amount, uint256 earned);
    event DefaultEdgeSet(
        uint128 amplitude,
        int24 lowTick,
        int24 highTick,
        uint24 fee,
        uint8 feeProtocol
    );
    /// Emitted when the adjustor is changed.
    event AdjustorChanged(
        address indexed admin,
        address fromAdjustor,
        address toAdjustor
    );
    /// Emitted when the efficiency factor for a token is changed.
    event EfficiencyFactorChanged(
        address indexed admin,
        address indexed token,
        uint256 fromEsX128,
        uint256 toEsX128
    );
    /// Emitted when search params are changed.
    event SearchParamsChanged(
        address indexed admin,
        uint8 maxIter,
        int256 deMinimusX128,
        int256 targetSlippageX128
    );

    /* Getters */

    /// @notice Gets earned protocol fees that have yet to be collected.
    function protocolEarnings() external returns (uint256[MAX_TOKENS] memory) {
        return SimplexLib.protocolEarnings();
    }

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
        TokenRegLib.register(token);
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

    /// @notice Withdraws the given token from the protocol.
    // Normally tokens supporting the AMM ALWAYS resides in the vaults.
    // The only exception is
    // 1. When fees are earned by the protocol.
    // 2. When someone accidentally sends tokens to this address.
    // 3. When someone donates.
    /// @dev Only callable by the contract owner.
    function withdraw(address token) external {
        AdminLib.validateOwner();

        uint256 balance = IERC20(token).balanceOf(address(this));

        if (TokenRegLib.isRegistered(token)) {
            uint8 idx = TokenRegLib.getIdx(token);
            uint256 earned = SimplexLib.protocolGive(idx);
            emit FeesWithdrawn(token, balance, earned);
        }

        if (balance > 0) {
            TransferHelper.safeTransfer(token, msg.sender, balance);
        }
    }

    /// @notice Gets the efficiency factors for all tokens.
    function getEsX128() external view returns (uint256[MAX_TOKENS] memory) {
        return SimplexLib.getEsX128();
    }

    /// @notice Gets the efficiency factor for a given token.
    /// @param token The address of the token.
    function getEX128(address token) external view returns (uint256) {
        return SimplexLib.getEX128(TokenRegLib.getIdx(token));
    }

    /// @notice Sets the efficiency factor for a given token.
    /// @param token The address of the token.
    /// @param eX128 The efficiency factor to set.
    /// @dev Only callable by the contract owner.
    function setEX128(address token, uint256 eX128) external {
        AdminLib.validateOwner();
        uint8 idx = TokenRegLib.getIdx(token);
        emit EfficiencyFactorChanged(
            msg.sender,
            token,
            SimplexLib.getEX128(idx),
            eX128
        );
        SimplexLib.setEX128(idx, eX128);
    }

    /// @notice Gets the current adjustor.
    function getAdjustor() external view returns (address) {
        return SimplexLib.getAdjustor();
    }

    /// @notice Sets the adjustor.
    /// @dev Only callable by the contract owner.
    function setAdjustor(address adjustor) external {
        AdminLib.validateOwner();

        emit AdjustorChanged(msg.sender, SimplexLib.getAdjustor(), adjustor);
        SimplexLib.setAdjustor(adjustor);

        address[] memory tokens = Store.tokenRegistry().tokens;
        for (uint8 i = 0; i < tokens.length; ++i) {
            IAdjustor(adjustor).cacheAdjustment(tokens[i]);
        }
    }

    /// @notice Gets the current search params.
    function getSearchParams()
        external
        view
        returns (SearchParams memory params)
    {
        return SimplexLib.getSearchParams();
    }

    /// @notice Sets the search params.
    /// @dev Only callable by the contract owner.
    function setSearchParams(SearchParams calldata params) external {
        AdminLib.validateOwner();

        if (params.deMinimusX128 <= 0) {
            revert NonPositiveDeMinimusX128(params.deMinimusX128);
        }

        SimplexLib.setSearchParams(params);

        emit SearchParamsChanged(
            msg.sender,
            params.maxIter,
            params.deMinimusX128,
            params.targetSlippageX128
        );
    }

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
