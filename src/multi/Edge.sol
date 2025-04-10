// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MAX_TOKENS} from "./Token.sol";
import {VertexId} from "./vertex/Vertex.sol";

/*
    Facilitates all swaps.
 */
struct Edge {
    /* Swap info */
    uint256 baseFeeX128; // The flat fee we charge on all swaps.
    uint256 protocolFeeX128; //
    uint256[MAX_TOKENS] esX128; // The scale factor we use to boost capital efficiency.
    /*
    The value equation we use for each token (balance x) is:
    v(x) = (e + 2) * t - ((e + 1)t)^2 / (x + e*t)
    e - The capital efficiency factor. Sets our price range this would support.
    t - The target balance of the token. The minimum slippage occurs when x = t.
    The value matches the token balance at equilibrium (t = x) and the price is 1 then.
    */
}

using EdgeImpl for Edge global;

library EdgeImpl {
    error MisconfiguredFees();

    // Admin function to set edge's swap concentration.
    function setE(Edge storage self, uint8 idx, uint256 eX128) internal {
        // There's no real sanitiy check for this because all non-negative values are potentially valid.
        self.esX128[idx] = eX128;
    }

    function setFees(
        Edge storage self,
        uint256 baseX128,
        uint256 protocolX128
    ) internal {
        require(baseX128 > protocolX128, MisconfiguredFees());
        // Again, all non-negative values are valid.
        self.baseFeeX128 = baseX128;
        self.protocolFeeX128 = protocolX128;
    }

    /* Actions to take on an edge (hyper-edge) */

    function swapIn()

    /* Price functions used by LiqFacet */

    /// Fetch the REAL price implied by these balances on this edge denoted in terms of token1.
    /// @dev This ALWAYS rounds up due to its usage in Add.
    /// @param balance0 This is the balance of token0
    /// @param balance1 This is the balance of token1
    /// @return priceX128 This is the price denoted with token1 as the numeraire.
    function getPriceX128(
        Edge storage self,
        uint128 balance0,
        uint128 balance1
    ) internal view returns (uint256 priceX128) {
        (uint256 sqrtPriceX96, ) = calcImpliedHelper(
            self,
            balance0,
            balance1,
            true
        );

        return FullMath.mulX128(sqrtPriceX96, sqrtPriceX96 << 64, true);
    }

    /// Fetch the price implied by these balances on this edge denoted in terms of token0.
    /// @dev This ALWAYS rounds up due to its usage in Add.
    /// @param balance0 This is the balance of token0
    /// @param balance1 This is the balance of token1
    /// @return invPriceX128 This is the price denoted with token0 as the numeraire.
    function getInvPriceX128(
        Edge storage self,
        uint128 balance0,
        uint128 balance1
    ) internal view returns (uint256 invPriceX128) {
        (uint256 sqrtPriceX96, ) = calcImpliedHelper(
            self,
            balance0,
            balance1,
            false // Round down to round inv up.
        );
        uint256 invSqrtX128 = X224 / sqrtPriceX96;
        if (X224 % sqrtPriceX96 > 0) invSqrtX128 += 1;
        return FullMath.mulX128(invSqrtX128, invSqrtX128, true);
    }

    /* Helpers */

    function sqrt(uint x) private pure returns (uint y) {
        if (x == 0) return 0;
        else if (x <= 3) return 1;
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

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
}
