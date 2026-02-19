// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BurveForkableTest} from "../Fork.u.sol";
import {Swapper} from "../../../src/integrations/swapper/Swapper.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {Create2Deployer} from "../../utils/Create2Deployer.sol";
import {IBurveMultiValue} from "../../../src/multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "../../../src/multi/facets/ValueTokenFacet.sol";

contract TestSwapper is BurveForkableTest {
    Swapper swapper;
    Create2Deployer create2Deployer;
    bytes32 internal constant SWAPPER_SALT = keccak256("swapper-test-salt");

    function deploySwapperDeterministically() internal returns (Swapper) {
        if (address(create2Deployer) == address(0)) {
            create2Deployer = new Create2Deployer();
        }
        bytes memory bytecode = abi.encodePacked(
            type(Swapper).creationCode,
            abi.encode(0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7)
        );
        address addr = create2Deployer.deploy(bytecode, SWAPPER_SALT);
        return Swapper(addr);
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
    /// collect earnings to the Swapper, then call swapAndForward to consolidate into USDC.
    function testSwapAndForwardTwoToken() public forkOnly {
        swapper = deploySwapperDeterministically();

        address[] memory poolTokens = IBurveMultiSimplex(diamond).getTokens();
        uint16 closureId = 3; // USDC (idx 0) + USDT (idx 1)
        address outToken = poolTokens[0]; // USDC

        // --- Open position ---
        uint256 posValue = _openPosition(closureId, 1e15);
        console2.log("opened position value", posValue);
        assertGt(posValue, 0, "position should exist");

        // --- Collect earnings to Swapper ---
        IBurveMultiValue(diamond).collectEarnings(
            address(swapper),
            closureId
        );

        // --- swapAndForward ---
        // No router txData — the outToken's portion from collectEarnings flows through.
        // Non-outToken stays in the swapper (in production OogaBooga txData would swap it).
        address[] memory inTokens = new address[](1);
        inTokens[0] = poolTokens[1]; // USDT
        bytes[] memory txData = new bytes[](1);
        // empty txData[0] — skip USDT swap

        uint256 outBefore = IERC20(outToken).balanceOf(address(this));
        uint256 totalOut = swapper.swapAndForward(
            outToken,
            inTokens,
            txData,
            0
        );
        uint256 outAfter = IERC20(outToken).balanceOf(address(this));

        // --- Assertions ---
        assertEq(outAfter - outBefore, totalOut, "balance delta == totalOut");
        console2.log("USDC received from swapAndForward", totalOut);

        // Position should still exist (we only collected earnings, not removed value).
        (uint256 posAfter, ) = ValueTokenFacet(diamond).balanceOf(
            address(this),
            closureId
        );
        assertEq(posAfter, posValue, "position should remain intact");
    }

    /// Same flow with a three-token closure (USDC+USDT+HONEY).
    function testSwapAndForwardThreeToken() public forkOnly {
        swapper = deploySwapperDeterministically();

        address[] memory poolTokens = IBurveMultiSimplex(diamond).getTokens();
        uint16 closureId = 7; // USDC (idx 0) + USDT (idx 1) + HONEY (idx 2)
        address outToken = poolTokens[0]; // USDC

        // --- Open position ---
        uint256 posValue = _openPosition(closureId, 1e15);
        console2.log("opened position value", posValue);
        assertGt(posValue, 0, "position should exist");

        // --- Collect earnings to Swapper ---
        IBurveMultiValue(diamond).collectEarnings(
            address(swapper),
            closureId
        );

        // --- swapAndForward ---
        address[] memory inTokens = new address[](2);
        inTokens[0] = poolTokens[1]; // USDT
        inTokens[1] = poolTokens[2]; // HONEY
        bytes[] memory txData = new bytes[](2);
        // empty txData — skip all swaps

        uint256 outBefore = IERC20(outToken).balanceOf(address(this));
        uint256 totalOut = swapper.swapAndForward(
            outToken,
            inTokens,
            txData,
            0
        );
        uint256 outAfter = IERC20(outToken).balanceOf(address(this));

        // --- Assertions ---
        assertEq(outAfter - outBefore, totalOut, "balance delta == totalOut");
        console2.log("USDC received from swapAndForward", totalOut);

        (uint256 posAfter, ) = ValueTokenFacet(diamond).balanceOf(
            address(this),
            closureId
        );
        assertEq(posAfter, posValue, "position should remain intact");
    }
}
