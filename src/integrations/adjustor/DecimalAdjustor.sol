// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

type DecimalNormalizer is int256;

/// An Adjustor specific to decimals. You can inheret to add other forms of adjustment.
contract DecimalAdjustor {
    uint8 constant MAX_DECIMAL = 36; // We could handle up to 76, but why would we?
    uint256 constant ONE_X128 = 1 << 128;
    error TooManyDecimals(uint8);

    /* Often people reuse tokens so we save a bit of gas by storing old adjustments since they don't change. */
    // Positive when the real decimals is too small and we multiply,
    // negative when it's too large and we divide. It'll only be zero when uninitialized.
    mapping(address => int256) public adjustments;
    // For price ratios
    mapping(address num => mapping(address denom => uint256)) ratiosX128; // num / denom
    mapping(address num => mapping(address denom => bool)) ratioRounding; // Round up if true.

    /// Adjust real token values to a normalized value.
    /// @dev errors on overflow.
    function normalize(
        address token,
        uint256 value,
        bool roundUp
    ) external view returns (uint256 normalized) {
        int256 multiplier = getAdjustment(token);
        if (multiplier > 0) {
            return value * uint256(multiplier);
        } else {
            uint256 divisor = uint256(-multiplier);
            normalized = value / divisor;
            if (roundUp && ((value % divisor) > 0)) normalized += 1;
        }
    }

    /// Adjust a normalized token amount back to the real amount.
    function realize(
        address token,
        uint256 value,
        bool roundUp
    ) external view returns (uint256 denormalized) {
        int256 divisor = getAdjustment(token);
        if (divisor > 0) {
            uint256 div = uint256(divisor);
            denormalized = value / div;
            if (roundUp && ((value % div) > 0)) denormalized += 1;
        } else {
            uint256 multiplier = uint256(-divisor);
            return value * multiplier;
        }
    }

    /// Get the ratio to convert a real price to a nominal price given a ratio of two tokens.
    function normalizingRatioX128(
        address numToken,
        address denomToken,
        bool roundUp
    ) public view returns (uint256 ratioX128) {
        ratioX128 = ratiosX128[numToken][denomToken];
        if (ratioX128 == 0) {
            bool willRound;
            (ratioX128, willRound) = calculateRatioX128(numToken, denomToken);
            ratiosX128[numToken][denomToken] = ratioX128;
            ratioRounding[numToken][denomToken] = willRound;
        }
        if (roundUp && ratioRounding[numToken][denomToken]) ratioX128 += 1;
    }

    /// Get the ratio to convert a nominal price to a real price.
    function realizingRatioX128(
        address numToken,
        address denomToken,
        bool roundUp
    ) external view returns (uint256 ratioX128) {
        /// This is just the multiplicative inverse of the normalizing ratio.
        normalizingRatioX128(denomToken, numToken, roundUp);
    }

    /* Core workhorse helpers */

    /// Calculate an adjustment. Positive for multiplication and negative for division.
    function calculateAdjustment(
        address token
    ) internal view virtual returns (int256) {
        uint8 dec = getDecimals(token);
        if (dec > MAX_DECIMAL) revert TooManyDecimals(dec);
        if (dec > 18) {
            return -int256(fastPow(dec - 18));
        } else {
            return int256(fastPow(18 - dec));
        }
    }

    function calculateRatioX128(
        address num,
        address denom
    ) internal view virtual returns (uint256 ratioX128, bool willRound) {
        uint8 numDec = getDecimals(num);
        uint8 denomDec = getDecimals(denom);
        if (numDec > denomDec) {
            // We know this must be less than 1e36 which fits in 120 bits.
            ratioX128 = fastPow(numDec - denomDec) << 128;
            // No rounding needed
        } else if (denomDec > numDec) {
            // We want to divide
            uint256 divisor = fastPow(denomDec - numDec);
            ratioX128 = ONE_X128 / divisor;
            willRound = (ONE_X128 % divisor) > 0;
        } else {
            ratioX128 = ONE_X128;
            // No rounding needed
        }
    }

    /* Helpers */

    /// Fetch the adjustment and cache it if necessary.
    function getAdjustment(address token) internal returns (int256 adj) {
        adj = adjustments[token];
        if (adj == 0) {
            adj = calculateAdjustment(token);
            adjustments[token] = adj;
        }
    }

    /// Compute 10 to the exp cheaply.
    function fastPow(uint8 exp) private pure returns (uint256 powed) {
        powed = 1;
        uint256 mult = 10;
        while (exp > 0) {
            if (exp & 0x1 != 0) {
                powed *= mult;
            }
            exp >>= 1;
            mult = mult * mult;
        }
    }

    function getDecimals(address token) internal returns (uint8 dec) {
        dec = IERC20(token).decimals();
        if (dec > MAX_DECIMAL) revert TooManyDecimals(dec);
    }
}
