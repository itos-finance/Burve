// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/// Adjustors are contracts that convert token balances in various ways.
/// For example, it re-normalizes non-18 decimal tokens to 18 decimals.
/// Or converts appreciating LSTs to the underlier's balance.
interface IAdjustor {
    function toNominal(uint256 balance) external view returns (uint256 real);
    function toReal(uint256 balance) external view returns (uint256 nominal);
}
