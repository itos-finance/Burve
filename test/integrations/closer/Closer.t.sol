// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;
import {BurveForkableTest} from "../Fork.u.sol";
import {Closer} from "../../../src/integrations/closer/Closer.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {Create2Deployer} from "../../utils/Create2Deployer.sol";
import {IBurveMultiValue} from "../../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "../../../src/multi/facets/ValueTokenFacet.sol";

contract TestCloser is BurveForkableTest {
    Closer closer;
    Create2Deployer create2Deployer;
    bytes32 internal constant CLOSER_SALT = keccak256("closer-test-salt");

    function deployCloserDeterministically() internal returns (Closer) {
        if (address(create2Deployer) == address(0)) {
            create2Deployer = new Create2Deployer();
        }
        bytes memory bytecode = abi.encodePacked(
            type(Closer).creationCode,
            abi.encode(0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7)
        );
        address addr = create2Deployer.deploy(bytecode, CLOSER_SALT);
        return Closer(addr);
    }

    /// Helper: deal tokens for a closure, approve the diamond, and addValue to open a position.
    /// @return posValue The value of the opened position.
    function _openPosition(
        uint16 closureId,
        uint128 depositValue
    ) internal returns (uint256 posValue) {
        address[] memory poolTokens = IBurveMultiSimplex(diamond).getTokens();
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if ((1 << i) & closureId > 0) {
                deal(poolTokens[i], address(this), 10_000e18);
                IERC20(poolTokens[i]).approve(diamond, type(uint256).max);
            }
        }
        uint256[MAX_TOKENS] memory addLimits;
        IBurveMultiValue(diamond).addValue(
            address(this),
            closureId,
            depositValue,
            0,
            addLimits
        );
        (posValue, ) = ValueTokenFacet(diamond).balanceOf(
            address(this),
            closureId
        );
    }

    /// Open a position on the live Burve stablecoin pool (closure 3 = USDC+USDT),
    /// then close it with the Closer, receiving USDC as the outToken.
    function testOpenAndCloseTwoToken() public forkOnly {
        closer = deployCloserDeterministically();

        address[] memory poolTokens = IBurveMultiSimplex(diamond).getTokens();
        uint16 closureId = 3; // USDC (idx 0) + USDT (idx 1)
        address outToken = poolTokens[0]; // USDC

        // --- Open ---
        uint256 posValue = _openPosition(closureId, 1e15);
        console2.log("opened position value", posValue);
        assertGt(posValue, 0, "position should exist");

        // --- Approve Closer ---
        ValueTokenFacet(diamond).approve(
            address(closer),
            closureId,
            posValue,
            0
        );

        // --- Close ---
        // No swap txData — the outToken's proportional share from removeValue
        // is forwarded to the user. The other token stays in the Closer.
        // In production the txData would swap USDT->USDC via OogaBooga.
        bytes[MAX_TOKENS] memory txData;
        uint256[MAX_TOKENS] memory minAmountsReceived;

        uint256 outBefore = IERC20(outToken).balanceOf(address(this));
        uint256 totalOut = closer.burn(
            diamond,
            outToken,
            closureId,
            uint128(posValue),
            0,
            txData,
            minAmountsReceived,
            0
        );
        uint256 outAfter = IERC20(outToken).balanceOf(address(this));

        // --- Assertions ---
        assertEq(outAfter - outBefore, totalOut, "balance delta == totalOut");
        assertGt(totalOut, 0, "should receive outToken");
        console2.log("USDC received from close", totalOut);

        // Position should be fully closed.
        (uint256 posAfter, ) = ValueTokenFacet(diamond).balanceOf(
            address(this),
            closureId
        );
        assertEq(posAfter, 0, "position should be fully closed");

        // The non-outToken (USDT) portion sits in the Closer (no swap was executed).
        uint256 closerUsdtBalance = IERC20(poolTokens[1]).balanceOf(
            address(closer)
        );
        console2.log("USDT remaining in closer", closerUsdtBalance);
        assertGt(closerUsdtBalance, 0, "USDT should remain in closer (no swap)");
    }

    /// Same flow with a three-token closure (USDC+USDT+HONEY).
    function testOpenAndCloseThreeToken() public forkOnly {
        closer = deployCloserDeterministically();

        address[] memory poolTokens = IBurveMultiSimplex(diamond).getTokens();
        uint16 closureId = 7; // USDC (idx 0) + USDT (idx 1) + HONEY (idx 2)
        address outToken = poolTokens[0]; // USDC

        // --- Open ---
        uint256 posValue = _openPosition(closureId, 1e15);
        console2.log("opened position value", posValue);
        assertGt(posValue, 0, "position should exist");

        // --- Approve Closer ---
        ValueTokenFacet(diamond).approve(
            address(closer),
            closureId,
            posValue,
            0
        );

        // --- Close ---
        bytes[MAX_TOKENS] memory txData;
        uint256[MAX_TOKENS] memory minAmountsReceived;

        uint256 outBefore = IERC20(outToken).balanceOf(address(this));
        uint256 totalOut = closer.burn(
            diamond,
            outToken,
            closureId,
            uint128(posValue),
            0,
            txData,
            minAmountsReceived,
            0
        );
        uint256 outAfter = IERC20(outToken).balanceOf(address(this));

        // --- Assertions ---
        assertEq(outAfter - outBefore, totalOut, "balance delta == totalOut");
        assertGt(totalOut, 0, "should receive outToken");
        console2.log("USDC received from close", totalOut);

        (uint256 posAfter, ) = ValueTokenFacet(diamond).balanceOf(
            address(this),
            closureId
        );
        assertEq(posAfter, 0, "position should be fully closed");

        // USDT and HONEY remain in the Closer (no swaps).
        assertGt(
            IERC20(poolTokens[1]).balanceOf(address(closer)),
            0,
            "USDT should remain in closer"
        );
        assertGt(
            IERC20(poolTokens[2]).balanceOf(address(closer)),
            0,
            "HONEY should remain in closer"
        );
    }
}
