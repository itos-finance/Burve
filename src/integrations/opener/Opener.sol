// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {IRFTPayer} from "Commons/Util/RFT.sol";

import {IOBRouter} from "./IOBRouter.sol";
import {IBurveMultiValue} from "../../multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../multi/interfaces/IBurveMultiSimplex.sol";
import {IAdjustor} from "../adjustor/IAdjustor.sol";

import {FullMath} from "../../FullMath.sol";
import {MAX_TOKENS} from "../../multi/Constants.sol";

contract Opener is IRFTPayer {
    address BEPOLIA_EXECUTOR = 0xADEC0cE4efdC385A44349bD0e55D4b404d5367B4;
    address BERACHAIN_EXECUTOR = 0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;

    IOBRouter router;
    uint256[] amountsOut;

    constructor() {
        router = IOBRouter(BEPOLIA_EXECUTOR);
    }

    error InvalidCaller();
    error OogaBoogaFailure();

    function mint(
        address pool,
        address[] calldata tokens,
        bytes[] calldata txData,
        uint16 closureId,
        uint256 nonSwappingAmount,
        uint256 bgtPercentX256,
        uint256[MAX_TOKENS] memory amountLimits
    ) external {
        amountsOut[0] = nonSwappingAmount;
        /// note we start from index 1
        for (uint256 i = 1; i < txData.length; i++) {
            (bool success, bytes memory data) = BEPOLIA_EXECUTOR.call(
                txData[i]
            );

            if (!success) revert OogaBoogaFailure();

            // store the amountOut from the oogabooga swap
            amountsOut[i] = abi.decode(data, (uint256));
        }

        // calculate the max value to add
        (
            uint8 n,
            uint256 targetX128,
            uint256[MAX_TOKENS] memory balances,
            ,

        ) = IBurveMultiSimplex(pool).getClosureValue(closureId);

        address adjustor = IBurveMultiSimplex(pool).getAdjustor();
        uint256[] memory closureBalances = new uint256[](n);
        uint256 j = 0;
        for (uint256 i = 0; i < balances.length; i++) {
            if (balances[i] == 0) continue;
            closureBalances[j] = IAdjustor(adjustor).toReal(
                tokens[j],
                balances[i],
                true
            );
            j++;
        }

        uint256[] percentagesX128 = new uint256[](n);
        for (uint256 i = 0; i < closureBalances.length; i++) {
            percentagesX128[i] = (amountsOut[i] << 128) / closureBalances[i];
        }

        uint256 minValue = type(uint256).max;
        for (uint256 i = 0; i < percentagesX128; i++) {
            uint256 target = (targetX128 * percentagesX128[i]) /
                (1 << 128) /
                (1 << 128);
            uint256 value = target * n;
            if (value < minValue) {
                minValue = value;
            }
        }

        uint256 bgtValue = (minValue * bgtPercentX256) / (1 << 256);

        IBurveMultiValue(pool).addValue(
            msg.sender,
            closureId,
            value,
            bgtValue,
            amountLimits
        );

        // single deposit any remaining amounts of each token
        for (uint256 i = 0; i < amountsOut.length; i++) {
            if (amountsOut[i] > 0) {
                IBurveMultiValue(pool).addSingleForValue(
                    msg.sender,
                    closureId,
                    tokens[i],
                    amountsOut[i],
                    bgtPercentX256, // lazy
                    0
                );
                amountsOut[i] = 0;
            }
        }
    }

    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata data
    ) external returns (bytes memory cbData) {
        /// if the tokens length is one, its a addSingleForValue deposit, therefore we don't need to do the additional accounting
        if (tokens.length == 1) {
            TransferHelper.safeTransfer(
                tokens[0],
                msg.sender,
                uint256(requests[0])
            );
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            TransferHelper.safeTransfer(
                tokens[i],
                msg.sender,
                uint256(requests[i])
            );
            amountsOut[i] -= uint256(requests[i]);
        }
    }
}
