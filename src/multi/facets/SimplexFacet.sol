// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {AdminLib} from "Commons/Util/Admin.sol";
import {TokenRegLib, TokenRegistry, MAX_TOKENS} from "../Token.sol";
import {IAdjustor} from "../../integrations/adjustor/IAdjustor.sol";
import {IBurveMultiEvents} from "../interfaces/IBurveMultiEvents.sol";
import {AdjustorLib} from "../Adjustor.sol";
import {ClosureId} from "../closure/Id.sol";
import {Closure} from "../closure/Closure.sol";
import {ReserveLib} from "../vertex/Reserve.sol";
import {SearchParams} from "../Value.sol";
import {Simplex, SimplexLib} from "../Simplex.sol";
import {Store} from "../Store.sol";
import {TransferHelper} from "../../TransferHelper.sol";
import {VaultLib, VaultProxy, VaultType} from "../vertex/VaultProxy.sol";
import {Vertex} from "../vertex/Vertex.sol";
import {VertexId, VertexLib} from "../vertex/Id.sol";
import {ValueLib} from "../Value.sol";

contract SimplexAdminFacet {
    event VertexAdded(
        address indexed token,
        address indexed vault,
        VertexId vid,
        VaultType vaultType
    );
    event ProtocolFeesWithdrawn(
        address indexed token,
        uint256 amount,
        uint256 earned
    );

    /// Thrown when adding a closure if the specified starting target is less than the required init target.
    error InsufficientStartingTarget(
        uint128 startingTarget,
        uint256 initTarget
    );
    /* Admin Function */

    /// @notice Adds a vertex.
    /// @dev Only callable by the contract owner.
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

    /// @notice Adds a closure.
    /// @dev Only callable by the contract owner.
    function addClosure(uint16 _cid, uint128 startingTarget) external {
        AdminLib.validateOwner();

        ClosureId cid = ClosureId.wrap(_cid);
        // We fetch the raw storage because Store.closure would check the closure for initialization.
        Closure storage c = Store.load().closures[cid];

        uint256 initTarget = Store.simplex().initTarget;
        if (startingTarget < initTarget) {
            revert InsufficientStartingTarget(startingTarget, initTarget);
        }

        uint256[MAX_TOKENS] storage neededBalances = c.init(
            cid,
            startingTarget
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
    function withdraw(address token) external returns (uint256 amount) {
        AdminLib.validateOwner();

        if (TokenRegLib.isRegistered(token)) {
            uint8 idx = TokenRegLib.getIdx(token);
            uint256 earned = SimplexLib.protocolGive(idx);
            amount = ReserveLib.withdraw(VertexLib.newId(token), earned);
        }

        // After withdrawing, we combine it with any dust or stray tokens left on this contract.
        // All user funds would be safe in the vaults. Any funds on this contract are not supposed to be here.
        uint256 balance = IERC20(token).balanceOf(address(this));

        if (balance > 0) {
            emit ProtocolFeesWithdrawn(token, balance, amount);
            TransferHelper.safeTransfer(token, msg.sender, balance);
        }
    }
}

contract SimplexSetFacet {
    /// Thrown when setting the BGT exchanger if the provided address is the zero address.
    error BGTExchangerIsZeroAddress();
    /// Throw when setting search params if deMinimusX128 is not positive.
    error NonPositiveDeMinimusX128(int256 deMinimusX128);

    event NewName(string newName, string symbol);

    /// Emitted when the adjustor is changed.
    event AdjustorChanged(
        address indexed admin,
        address fromAdjustor,
        address toAdjustor
    );
    /// Emitted when the BGT exchanger is changed.
    event BGTExchangerChanged(
        address indexed admin,
        address indexed fromExchanger,
        address indexed toExchanger
    );
    /// Emitted when the efficiency factor for a token is changed.
    event EfficiencyFactorChanged(
        address indexed admin,
        address indexed token,
        uint256 fromEsX128,
        uint256 toEsX128
    );
    /// Emitted when the init target is changed.
    event InitTargetChanged(
        address indexed admin,
        uint256 fromInitTarget,
        uint256 toInitTarget
    );
    /// Emitted when search params are changed.
    event SearchParamsChanged(
        address indexed admin,
        uint8 maxIter,
        int256 deMinimusX128,
        int256 targetSlippageX128
    );

    /* Setters */

    /// @notice Sets the efficiency factor for a given token.
    /// @param token The address of the token.
    /// @param eX128 The efficiency factor to set.
    /// @dev Only callable by the contract owner.
    function setEX128(address token, uint256 eX128) external {
        AdminLib.validateOwner();
        uint8 idx = TokenRegLib.getIdx(token);
        uint256 oldEX128 = SimplexLib.setEX128(idx, eX128);
        emit EfficiencyFactorChanged(msg.sender, token, oldEX128, eX128);

        // Now that E is changed, we need to adjust the balances in the closures.
        bool concentrate = eX128 > oldEX128;
        VertexId vid = VertexLib.newId(idx);

        // For deposits when not concentrating.
        uint256 needed = 0;
        VaultProxy memory vProxy = VaultLib.getProxy(vid);
        Vertex storage v = Store.vertex(vid);

        // We need to make sure the value is the same before and after the change in E
        // and the necessary balance changes are made.
        uint8 n = TokenRegLib.numVertices();
        uint16 idxBit = uint16(1 << idx);
        uint32 maxCid = uint32((1 << n) - 1); // Use 32 to not overflow.
        for (uint32 cid = 0; cid <= maxCid; ++cid) {
            if (cid & idxBit == 0) continue; // Skip if the vertex is not in the closure.
            ClosureId _cid = ClosureId.wrap(uint16(cid));
            (Closure storage c, bool exists) = Store.tryClosure(_cid);
            if (!exists) continue; // Skip if the closure does not exist.
            uint256 valueX128 = ValueLib.v(
                c.targetX128,
                oldEX128,
                c.balances[idx],
                true
            );
            uint256 oldX = c.balances[idx];
            c.balances[idx] = ValueLib.x(c.targetX128, eX128, valueX128, true);
            if (concentrate) {
                // If we're concentrating, the balance needed is smaller so we trim.
                c.trimBalance(vid);
            } else {
                // If we're expanding the range, we'll need more tokens to get the same value.
                uint256 singleDeposit = c.balances[idx] - oldX;
                needed += singleDeposit;
                v.deposit(vProxy, _cid, singleDeposit);
            }
        }
        if (needed > 0) {
            TransferHelper.safeTransferFrom(
                token,
                msg.sender,
                address(this),
                needed
            );
            // Commit the deposits now that we have the tokens.
            vProxy.commit();
        }
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

    /// @notice Sets the BGT exchanger
    /// @dev Only callable by the contract owner.
    /// Migration to the next BGT exchanger should be completed before calling this function.
    /// 1. Set the previous BGT exchanger as the backup on the next BGT exchanger.
    /// 2. Add this contract as an allowed exchanger on the next BGT exchanger.
    /// 3. Send the balance on the previous BGT exchanger to the next BGT exchanger.
    function setBGTExchanger(address bgtExchanger) external {
        AdminLib.validateOwner();
        if (bgtExchanger == address(0x0)) revert BGTExchangerIsZeroAddress();
        emit BGTExchangerChanged(
            msg.sender,
            SimplexLib.getBGTExchanger(),
            bgtExchanger
        );
        SimplexLib.setBGTExchanger(bgtExchanger);
    }

    /// @notice Sets the init target.
    function setInitTarget(uint256 initTarget) external {
        AdminLib.validateOwner();
        emit InitTargetChanged(
            msg.sender,
            SimplexLib.getInitTarget(),
            initTarget
        );
        SimplexLib.setInitTarget(initTarget);
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

    /// @notice Sets the name and symbol for the value token.
    /// @dev Only callable by the contract owner.
    function setName(
        string calldata newName,
        string calldata newSymbol
    ) external {
        AdminLib.validateOwner();

        Simplex storage s = Store.simplex();
        s.name = newName;
        s.symbol = newSymbol;

        emit NewName(newName, newSymbol);
    }

    function setSimplexFees(
        uint128 defaultEdgeFeeX128,
        uint128 protocolTakeX128
    ) external {
        AdminLib.validateOwner();

        Simplex storage s = Store.simplex();
        s.defaultEdgeFeeX128 = defaultEdgeFeeX128;
        s.protocolTakeX128 = protocolTakeX128;

        emit IBurveMultiEvents.SimplexFeesSet(
            defaultEdgeFeeX128,
            protocolTakeX128
        );
    }

    /// @notice Sets fees for a given edge.
    function setEdgeFee(uint8 idx0, uint8 idx1, uint128 edgeFeeX128) external {
        AdminLib.validateOwner();

        if (idx0 > idx1) {
            (idx0, idx1) = (idx1, idx0);
        }

        VertexId i = VertexLib.newId(idx0);
        VertexId j = VertexLib.newId(idx1);

        SimplexLib.setEdgeFeeX128(i, j, edgeFeeX128);
        emit IBurveMultiEvents.EdgeFeeSet(idx0, idx1, edgeFeeX128);
    }
}

contract SimplexGetFacet {
    /* Getters */

    /// @notice Gets the name and symbol for the value token.
    function getName()
        external
        view
        returns (string memory name, string memory symbol)
    {
        Simplex storage s = Store.simplex();
        name = s.name;
        symbol = s.symbol;
    }

    /// @notice Get everything value-related about a closure.
    function getClosureValue(
        uint16 closureId
    )
        external
        view
        returns (
            uint8 n,
            uint256 targetX128,
            uint256[MAX_TOKENS] memory balances,
            uint256 valueStaked,
            uint256 bgtValueStaked
        )
    {
        Closure storage c = Store.closure(ClosureId.wrap(closureId));
        n = c.n;
        targetX128 = c.targetX128;
        valueStaked = c.valueStaked;
        bgtValueStaked = c.bgtValueStaked;
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            balances[i] = c.balances[i];
        }
    }

    /// @notice Get everything fee-related about a closure.
    function getClosureFees(
        uint16 closureId
    )
        external
        view
        returns (
            uint256[MAX_TOKENS] memory earningsPerValueX128,
            uint256 bgtPerBgtValueX128,
            uint256[MAX_TOKENS] memory unexchangedPerBgtValueX128
        )
    {
        Closure storage c = Store.closure(ClosureId.wrap(closureId));
        bgtPerBgtValueX128 = c.bgtPerBgtValueX128;
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            earningsPerValueX128[i] = c.earningsPerValueX128[i];
            unexchangedPerBgtValueX128[i] = c.unexchangedPerBgtValueX128[i];
        }
    }

    /// @notice Gets the default edge fee and protocol take.
    function getSimplexFees()
        external
        view
        returns (uint128 defaultEdgeFeeX128, uint128 protocolTakeX128)
    {
        Simplex storage s = Store.simplex();
        return (s.defaultEdgeFeeX128, s.protocolTakeX128);
    }

    /// @notice Gets the default edge fee for a given token.
    function getEdgeFee(
        uint8 idx0,
        uint8 idx1
    ) external view returns (uint128 edgeFeeX128) {
        return
            SimplexLib.getEdgeFeeX128(
                VertexLib.newId(idx0),
                VertexLib.newId(idx1)
            );
    }

    /// @notice Gets earned protocol fees that have yet to be collected.
    function protocolEarnings()
        external
        view
        returns (uint256[MAX_TOKENS] memory)
    {
        return SimplexLib.protocolEarnings();
    }

    /// @notice Gets the list of registered tokens.
    function getTokens() external view returns (address[] memory) {
        return Store.tokenRegistry().tokens;
    }

    /// @notice Gets the number of currently installed vertices
    function getNumVertices() external view returns (uint8) {
        return TokenRegLib.numVertices();
    }

    /// @notice Gets the index of a registered token by address.
    function getIdx(address token) external view returns (uint8) {
        return TokenRegLib.getIdx(token);
    }

    /// @notice Gets the vertex Id of a token by address.
    function getVertexId(address token) external view returns (uint24) {
        return VertexId.unwrap(VertexLib.newId(token));
    }
    /// @notice Gets the current search params.
    function getSearchParams()
        external
        view
        returns (SearchParams memory params)
    {
        return SimplexLib.getSearchParams();
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

    /// @notice Gets the current adjustor.
    function getAdjustor() external view returns (address) {
        return SimplexLib.getAdjustor();
    }

    /// @notice Gets the current BGT exchanger.
    function getBGTExchanger() external view returns (address) {
        return SimplexLib.getBGTExchanger();
    }

    /// @notice Gets the current init target.
    function getInitTarget() external view returns (uint256) {
        return SimplexLib.getInitTarget();
    }
}
