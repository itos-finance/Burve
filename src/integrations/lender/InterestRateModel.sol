// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {FullMath} from "../../FullMath.sol";

/// @title InterestRateModel
/// @notice Two-slope utilization-based interest rate model.
///         Base rate: 2% APR
///         Slope 1 (0-80% utilization): +4% at optimal
///         Slope 2 (80-100% utilization): +75% at 100%
///         Reserve factor: 10%
library InterestRateModel {
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;
    uint256 internal constant X128 = 1 << 128;

    // Rate parameters (annualized, scaled by 1e18 = 100%)
    uint256 internal constant BASE_RATE = 2e16;           // 2%
    uint256 internal constant SLOPE1 = 4e16;              // 4%
    uint256 internal constant SLOPE2 = 75e16;             // 75%
    uint256 internal constant OPTIMAL_UTILIZATION = 80e16; // 80%
    uint256 internal constant RESERVE_FACTOR = 10e16;      // 10%
    uint256 internal constant PRECISION = 1e18;

    /// @notice Calculate the annualized borrow rate (1e18 = 100%).
    function getBorrowRate(
        uint256 totalBorrowed,
        uint256 totalDeposited
    ) internal pure returns (uint256 borrowRate) {
        if (totalDeposited == 0) return BASE_RATE;

        // Fix: use FullMath to avoid overflow on multiplication-before-division
        uint256 utilization = FullMath.mulDiv(totalBorrowed, PRECISION, totalDeposited);

        // Cap utilization at 100% to prevent underflow in slope2 branch
        if (utilization > PRECISION) utilization = PRECISION;

        if (utilization <= OPTIMAL_UTILIZATION) {
            borrowRate = BASE_RATE + FullMath.mulDiv(SLOPE1, utilization, OPTIMAL_UTILIZATION);
        } else {
            uint256 excessUtil = utilization - OPTIMAL_UTILIZATION;
            uint256 maxExcess = PRECISION - OPTIMAL_UTILIZATION;
            borrowRate = BASE_RATE + SLOPE1 + FullMath.mulDiv(SLOPE2, excessUtil, maxExcess);
        }
    }

    /// @notice Calculate the annualized supply rate (1e18 = 100%).
    function getSupplyRate(
        uint256 totalBorrowed,
        uint256 totalDeposited
    ) internal pure returns (uint256 supplyRate) {
        if (totalDeposited == 0) return 0;

        uint256 borrowRate = getBorrowRate(totalBorrowed, totalDeposited);
        uint256 utilization = FullMath.mulDiv(totalBorrowed, PRECISION, totalDeposited);
        if (utilization > PRECISION) utilization = PRECISION;

        // supplyRate = borrowRate * utilization * (1 - reserveFactor) / PRECISION^2
        supplyRate = FullMath.mulDiv(
            FullMath.mulDiv(borrowRate, utilization, PRECISION),
            PRECISION - RESERVE_FACTOR,
            PRECISION
        );
    }

    /// @notice Calculate the borrow index multiplier for a given time delta (Q128).
    function getBorrowMultiplierX128(
        uint256 totalBorrowed,
        uint256 totalDeposited,
        uint256 timeDelta
    ) internal pure returns (uint256) {
        uint256 borrowRate = getBorrowRate(totalBorrowed, totalDeposited);
        // multiplier = 1 + rate * timeDelta / SECONDS_PER_YEAR
        return X128 + FullMath.mulDiv(X128, borrowRate * timeDelta, SECONDS_PER_YEAR * PRECISION);
    }

    /// @notice Calculate the supply index multiplier for a given time delta (Q128).
    function getSupplyMultiplierX128(
        uint256 totalBorrowed,
        uint256 totalDeposited,
        uint256 timeDelta
    ) internal pure returns (uint256) {
        uint256 supplyRate = getSupplyRate(totalBorrowed, totalDeposited);
        return X128 + FullMath.mulDiv(X128, supplyRate * timeDelta, SECONDS_PER_YEAR * PRECISION);
    }
}
