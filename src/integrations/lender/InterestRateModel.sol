// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/// @title InterestRateModel
/// @notice Two-slope utilization-based interest rate model.
///         Base rate: 2% APR
///         Slope 1 (0–80% utilization): +4% at optimal
///         Slope 2 (80–100% utilization): +75% at 100%
///         Reserve factor: 10%
library InterestRateModel {
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;
    uint256 internal constant X128 = 1 << 128;

    // Rate parameters (per-second, scaled by 1e18)
    uint256 internal constant BASE_RATE = 2e16;          // 2%
    uint256 internal constant SLOPE1 = 4e16;              // 4%
    uint256 internal constant SLOPE2 = 75e16;             // 75%
    uint256 internal constant OPTIMAL_UTILIZATION = 80e16; // 80%
    uint256 internal constant RESERVE_FACTOR = 10e16;      // 10%
    uint256 internal constant PRECISION = 1e18;

    /// @notice Calculate the borrow rate per year (scaled by 1e18) given utilization.
    /// @param totalBorrowed Total amount currently borrowed.
    /// @param totalDeposited Total amount deposited by LPs.
    /// @return borrowRate The annualized borrow rate (1e18 = 100%).
    function getBorrowRate(
        uint256 totalBorrowed,
        uint256 totalDeposited
    ) internal pure returns (uint256 borrowRate) {
        if (totalDeposited == 0) return BASE_RATE;

        uint256 utilization = (totalBorrowed * PRECISION) / totalDeposited;

        if (utilization <= OPTIMAL_UTILIZATION) {
            // Linear interpolation: base + slope1 * (util / optimal)
            borrowRate = BASE_RATE + (SLOPE1 * utilization) / OPTIMAL_UTILIZATION;
        } else {
            // base + slope1 + slope2 * (util - optimal) / (1 - optimal)
            uint256 excessUtil = utilization - OPTIMAL_UTILIZATION;
            uint256 maxExcess = PRECISION - OPTIMAL_UTILIZATION;
            borrowRate = BASE_RATE + SLOPE1 + (SLOPE2 * excessUtil) / maxExcess;
        }
    }

    /// @notice Calculate the supply rate given the borrow rate and utilization.
    /// @param totalBorrowed Total amount currently borrowed.
    /// @param totalDeposited Total amount deposited by LPs.
    /// @return supplyRate The annualized supply rate (1e18 = 100%).
    function getSupplyRate(
        uint256 totalBorrowed,
        uint256 totalDeposited
    ) internal pure returns (uint256 supplyRate) {
        if (totalDeposited == 0) return 0;

        uint256 borrowRate = getBorrowRate(totalBorrowed, totalDeposited);
        uint256 utilization = (totalBorrowed * PRECISION) / totalDeposited;

        // supplyRate = borrowRate * utilization * (1 - reserveFactor)
        supplyRate = (borrowRate * utilization * (PRECISION - RESERVE_FACTOR)) / (PRECISION * PRECISION);
    }

    /// @notice Calculate the borrow index multiplier for a given time delta.
    /// @param totalBorrowed Total amount currently borrowed.
    /// @param totalDeposited Total amount deposited by LPs.
    /// @param timeDelta Seconds elapsed since last accrual.
    /// @return borrowMultiplierX128 Multiplier to apply to borrowIndexX128 (Q128).
    function getBorrowMultiplierX128(
        uint256 totalBorrowed,
        uint256 totalDeposited,
        uint256 timeDelta
    ) internal pure returns (uint256 borrowMultiplierX128) {
        uint256 borrowRate = getBorrowRate(totalBorrowed, totalDeposited);
        // multiplier = 1 + rate * timeDelta / SECONDS_PER_YEAR
        borrowMultiplierX128 = X128 + (X128 * borrowRate * timeDelta) / (SECONDS_PER_YEAR * PRECISION);
    }

    /// @notice Calculate the supply index multiplier for a given time delta.
    /// @param totalBorrowed Total amount currently borrowed.
    /// @param totalDeposited Total amount deposited by LPs.
    /// @param timeDelta Seconds elapsed since last accrual.
    /// @return supplyMultiplierX128 Multiplier to apply to supplyIndexX128 (Q128).
    function getSupplyMultiplierX128(
        uint256 totalBorrowed,
        uint256 totalDeposited,
        uint256 timeDelta
    ) internal pure returns (uint256 supplyMultiplierX128) {
        uint256 supplyRate = getSupplyRate(totalBorrowed, totalDeposited);
        supplyMultiplierX128 = X128 + (X128 * supplyRate * timeDelta) / (SECONDS_PER_YEAR * PRECISION);
    }
}
