// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MAX_TOKENS} from "../Constants.sol";
import {SearchParams} from "../Value.sol";
import {VaultType} from "../vertex/VaultProxy.sol";

interface IBurveMultiSimplex {
    /* Getters */
    function getName()
        external
        view
        returns (string memory name, string memory symbol);
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
        );
    function getClosureFees(
        uint16 closureId
    )
        external
        view
        returns (
            uint256[MAX_TOKENS] memory earningsPerValueX128,
            uint256 bgtPerBgtValueX128,
            uint256[MAX_TOKENS] memory unexchangedPerBgtValueX128
        );
    function getSimplexFees()
        external
        view
        returns (uint128 defaultEdgeFeeX128, uint128 protocolTakeX128);
    function getEdgeFee(
        uint8 idx0,
        uint8 idx1
    ) external view returns (uint128 edgeFeeX128);
    function protocolEarnings()
        external
        view
        returns (uint256[MAX_TOKENS] memory);
    function getTokens() external view returns (address[] memory);
    function getNumVertices() external view returns (uint8);
    function getIdx(address token) external view returns (uint8);
    function getVertexId(address token) external view returns (uint24);
    function getEsX128() external view returns (uint256[MAX_TOKENS] memory);
    function getEX128(address token) external view returns (uint256);
    function getAdjustor() external view returns (address);
    function getBGTExchanger() external view returns (address);
    function getInitTarget() external view returns (uint256);
    function getSearchParams()
        external
        view
        returns (SearchParams memory params);

    /* Admin Functions */
    function addVertex(address token, address vault, VaultType vType) external;
    function addClosure(uint16 _cid, uint128 startingTarget) external;
    function withdraw(address token) external returns (uint256 amount);
    /* Setters */
    function setEX128(address token, uint256 eX128) external;
    function setAdjustor(address adjustor) external;
    function setBGTExchanger(address bgtExchanger) external;
    function setInitTarget(uint256 initTarget) external;
    function setSearchParams(SearchParams calldata params) external;
    function setName(
        string calldata newName,
        string calldata newSymbol
    ) external;
    function setSimplexFees(
        uint128 defaultEdgeFeeX128,
        uint128 protocolTakeX128
    ) external;
    function setEdgeFee(uint8 idx0, uint8 idx1, uint128 edgeFeeX128) external;
}
