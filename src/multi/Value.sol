// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MAX_TOKENS} from "./Token.sol";
import {VertexId} from "./vertex/Vertex.sol";

library ValueLib {
    uint256 public constant TWOX128 = 2 << 128;

    /// Calculate the value of the current token balance (x).
    /// @param tX128 The target balance of this token.
    /// @param eX128 The capital efficiency factor of x.
    /// @param x The token balance. Won't go above 128 bits.
    function v(
        uint256 tX128,
        uint256 eX128,
        uint256 x,
        bool roundUp
    ) internal returns (uint256 valueX128) {
        uint256 etX128 = FullMath.mulX128(eX128, tX128, roundUp);
        valueX128 = etX128 + 2 * tX128;
        uint256 denomX128 = (x << 128) + etX128;
        uint256 sqrtNumX128 = etX128 + tX128;
        if (roundUp) {
            valueX128 += FullMath.mulDivRoundingUp(
                sqrtNumX128,
                sqrtNumX128,
                denomX128
            );
        } else {
            valueX128 += FullMath.mulDiv(sqrtNumX128, sqrtNumX128, denomX128);
        }
    }

    /// Given the desired value (vX128), what is the corresponding balance of the token.
    function x(
        uint256 tX128,
        uint256 eX128,
        uint256 vX128,
        bool roundUp
    ) internal returns (uint256 _x) {
        uint256 etX128 = FullMath.mulX128(eX128, tX128, roundUp);
        uint256 sqrtNumX128 = etX128 + tX128;
        // V is always less than (e + 2) * t
        uint256 denomX128 = etX128 + 2 * tX128 - vX128;
        uint256 xX128 = roundUp
            ? FullMath.mulDivRoundingUp(sqrtNumX128, sqrtNumX128, denomX128)
            : FullMath.mulDiv(sqrtNumX128, sqrtNumX128, denomX128);
        xX128 -= etX128;
        _x = xX128 >> 128;
        if (roundUp && ((xX128 << 128) != 0)) _x += 1;
    }

    /// Given the token balances for all tokens in a closure and their efficiency factors, determine the
    /// equilibriating target value.
    /// By convention we always round this down. On token adds, it under-dispenses value.
    /// On token removes, rounding down overdispenses value by 1, but we overcharge fees so its okay.
    function t(
        uint8 n,
        uint256[MAX_TOKENS] storage _esX128,
        uint256[MAX_TOKENS] storage _xs,
        uint256 tX128
    ) internal returns (uint256 targetX128) {
        // Setup
        uint256[] memory esX128 = new uint256[](n);
        uint256[] memory xs = new uint256[](n);
        uint8 j = 0;
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            if (_xs[i] > 0) {
                xs[j] = _xs[i];
                esX128[j] = _esX128[i];
                ++j;
            }
        }
        require(n == j, "Closure size mismatch");
        /// FOR NOW WE USE THIS WRONG METHOD JUST TO GET COMPILING.
        uint256 valueTotalX128;
        for (uint i = 0; i < n; ++i) {
            valueTotalX128 += v(tX128, esX128[i], xs[i], false);
        }
        // SO so so wrong.
        return valueTotalX128 / n;
        // TODO do the newtons method and write unittests for it.
        // Run newton's method.
        /*
        (
            uint8 maxIter,
            uint8 fudgeIter,
            uint8 lookBack,
            uint256 deMinimus
        ) = SimplexLib.newtonsParams();
        uint256 evaldF =
        while
        (tX128,  = tStep(t, esX128, xs, )
        */
    }

    /* Newtons method helpers for t */

    function dfdt(
        uint256 tX128,
        uint256[MAX_TOKENS] storage esX128,
        uint256[MAX_TOKENS] storage xs
    ) internal {}

    /// Calculate the derivative of v with respect to t.
    /// We only use this for solving for t with newtons method so careful rounding is less necessary.
    function dvdt(
        uint256 tX128,
        uint256 eX128,
        uint256 x
    ) internal returns (uint256 dvX128) {
        uint256 etX128 = FullMath.mulX128(eX128, tX128, false);
        dvX128 = eX128 + TWOX128;
        uint256 xX128 = x << 128;
        uint256 numAX128 = 2 * xX128 + etX128;
        uint256 numBX128 = tX128 +
            2 *
            etX128 +
            FullMath.mulX128(eX128, etX128, false);
        uint256 sqrtDenomX128 = xX128 + etX128;
        uint256 denomX128 = FullMath.mulX128(
            sqrtDenomX128,
            sqrtDenomX128,
            false
        );
        dvX128 -= FullMath.mulDiv(numAX128, numBX128, denomX128);
    }
}
