// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/// @notice Per-position loan data.
struct LoanPosition {
    address borrower;
    address pool;           // Burve diamond address
    uint16  closureId;
    address proxy;          // CREATE2 proxy holding this position in Burve
    uint256 depositedValue;
    uint256 depositedBgtValue;
}

/// @notice Per-token lending pool state.
struct LendingPool {
    uint256 totalDeposited;     // Total tokens deposited by LPs
    uint256 totalBorrowed;      // Total tokens currently borrowed
    uint256 borrowIndexX128;    // Cumulative interest index (Q128)
    uint256 supplyIndexX128;    // Cumulative supply index (Q128)
    uint256 lastAccrualTimestamp;
    uint256 totalShares;        // LP share tracking
}
