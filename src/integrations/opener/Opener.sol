// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {TransferHelper} from "Commons/Util/TransferHelper.sol";
import {IRFTPayer} from "Commons/Util/RFT.sol";
import {IOBRouter} from "./IOBRouter.sol";
import {IBurveMultiValue} from "../../multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../multi/interfaces/IBurveMultiSimplex.sol";
import {IAdjustor} from "../adjustor/IAdjustor.sol";
import {FullMath} from "../../FullMath.sol";
import {MAX_TOKENS} from "../../multi/Constants.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {SafeCast} from "Commons/Math/Cast.sol";

address constant BEPOLIA_EXECUTOR = 0xADEC0cE4efdC385A44349bD0e55D4b404d5367B4;
address constant BERACHAIN_EXECUTOR = 0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;

contract Opener is IRFTPayer, ReentrancyGuardTransient {
    address public immutable router;
    address public transient _pool;

    struct OogaboogaParams {
        IOBRouter.swapTokenInfo info;
        bytes pathDefinition;
        address executor;
        uint32 referralCode;
    }

    constructor(address _router) {
        router = _router;
    }

    error InvalidPool();
    error InvalidCaller();
    error InvalidRequest();
    error AmountSlippageExceeded();
    error ValueSlippageExceeded();
    error RouterFailure();

    function mint(
        address pool,
        uint8 inTokenIdx,
        uint256 inAmount,
        bytes[MAX_TOKENS] memory params,
        uint16 closureId,
        uint256 bgtPercentX256,
        uint256[MAX_TOKENS] calldata amountLimits,
        uint256 minValueReceived
    ) external nonReentrant returns (uint256 addedValue) {
        _pool = pool;

        address[] memory tokens = IBurveMultiSimplex(pool)
            .getTokens();
        require(tokens.length <= MAX_TOKENS, InvalidPool());
        uint256[] memory myBalances = new uint256[](tokens.length);

        // Get the tokens ready to send to the OB executor.
        TransferHelper.safeTransferFrom(
            tokens[inTokenIdx],
            msg.sender,
            address(this),
            inAmount
        );
        IERC20(tokens[inTokenIdx]).approve(
                router,
                inAmount
            );

        // Now get all our balances.
        for (uint256 i = 0; i < tokens.length; i++) {
            if (i == inTokenIdx) {
                continue;
            }
            
            // Skip tokens we don't want.
            if (params[i].length == 0) continue;

            // Swap for the tokens we do.
            (bool success, bytes memory data) = router.call(params[i]);
            if (!success) revert RouterFailure();

            // store the amountOut from the oogabooga swap
            myBalances[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
        myBalances[inTokenIdx] = IERC20(tokens[inTokenIdx]).balanceOf(address(this));

        // Determine how much value we can add.
        {
        (
            uint8 n,
            uint256 targetX128,
            uint256[MAX_TOKENS] memory closureBalances,
            ,

        ) = IBurveMultiSimplex(pool).getClosureValue(closureId);

        address adjustor = IBurveMultiSimplex(pool).getAdjustor();
        uint256 minPercentX256 = type(uint256).max;
        for (uint256 i = 0; i < closureBalances.length; i++) {
            if (closureBalances[i] == 0) continue;
            // We know closure balances line up with tokens
            uint256 realBalance = IAdjustor(adjustor).toReal(
                tokens[i],
                closureBalances[i],
                true
            );
            uint256 percentX256 = FullMath.mulDivX256(myBalances[i], realBalance, false);
            if (percentX256 < minPercentX256) {
                minPercentX256 = percentX256;
            }
        }

        // round the value we add down to make sure we fit.
        addedValue = FullMath.mulX128(
            FullMath.mulX256(targetX128, minPercentX256, false),
            n,
            false);
        }

        // Round up to handle the 100% case exactly.
        uint256 bgtValue = FullMath.mulX256(bgtPercentX256, addedValue, true);

        IBurveMultiValue(pool).addValue(
            msg.sender,
            closureId,
            SafeCast.toUint128(addedValue),
            uint128(bgtValue),
            amountLimits
        );

        // Single deposit any remaining amounts of each token
        for (uint256 i = 0; i < tokens.length; i++) {
            uint128 balance = SafeCast.toUint128(IERC20(tokens[i]).balanceOf(address(this)));
            if (balance > 0) {
                addedValue += IBurveMultiValue(pool).addSingleForValue(
                    msg.sender,
                    closureId,
                    tokens[i],
                    balance,
                    bgtPercentX256, // lazy
                    0
                );
            }
        }

        if (addedValue < minValueReceived) {
            revert ValueSlippageExceeded();
        }

        // Even though this will be cleared after the transaction, we still clear it now
        // as a pseudo-entrancy-check.
        _pool = address(0);
    }

    /// Simple RFT compliant payment callback that always pays debts.
    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata
    ) external returns (bytes memory _cbData) {
        // Let's check we're being called by who we expect.
        require(msg.sender == _pool, InvalidRequest());

        for (uint256 i = 0; i < tokens.length; i++) {
            TransferHelper.safeTransfer(
                tokens[i],
                msg.sender,
                SafeCast.toUint256(requests[i])
            );
        }
    }
}
