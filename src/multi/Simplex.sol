// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBGTExchanger} from "../integrations/BGTExchange/IBGTExchanger.sol";
import {MAX_TOKENS} from "./Constants.sol";
import {Store} from "./Store.sol";
import {TokenRegLib} from "./Token.sol";
import {ValueLib, SearchParams} from "./Value.sol";

// Stores information unchanged between all closures.
struct Simplex {
    string name;
    string symbol;
    address adjustor;
    address bgtEx;
    /// New closures are made with at least this much target value.
    uint256 initTarget;
    /// The efficiency factor for each token.
    uint256[MAX_TOKENS] esX128;
    /// A scaling factor for calculating the min acceptable x balance based on e.
    uint256[MAX_TOKENS] minXPerTX128;
    /// Amounts earned by the protocol for withdrawal.
    uint256[MAX_TOKENS] protocolEarnings;
    /// Parameters used by ValueLib.t to search
    SearchParams searchParams;
}

/// Convenient methods frequently requested by other parts of the pool.
library SimplexLib {
    // TODO:
    // Need a method for admin to withdraw protocol earnings.
    // Need a method to set efficiency factors (esX128) for each token.
    // A method to change bgtExchanger.
    // A method to change deminimus
    // A method to initTarget deminimus
    // Add a default e for new vertices to use.
    // A method to change adjustor.
    // Method to set search params by admin.

    function init(address adjustor) internal {
        Simplex storage s = Store.simplex();
        s.name = "N/A";
        s.symbol = "N/A";
        s.adjustor = adjustor;
        s.initTarget = 1e18; // reasonable default
        // Default to 10x efficient: price range is [0.84, 1.21].
        for (uint256 i = 0; i < MAX_TOKENS; ++i) {
            s.esX128[i] = 10 << 128;
            s.minXPerTX128[i] = ValueLib.calcMinXPerTX128(10 << 128);
        }
        s.searchParams.init();
    }

    /// @notice Gets earned protocol fees that have yet to be collected.
    function protocolEarnings()
        internal
        view
        returns (uint256[MAX_TOKENS] memory)
    {
        Simplex storage simplex = Store.simplex();
        return simplex.protocolEarnings;
    }

    /// @notice Adds amount to earned protocol fees for given token.
    /// @param idx The index of the token.
    /// @param amount The amount earned.
    function protocolTake(uint8 idx, uint256 amount) internal {
        Simplex storage simplex = Store.simplex();
        simplex.protocolEarnings[idx] += amount;
    }

    /// @notice Removes the earned protocol fees for given token.
    /// @param idx The index of the token.
    /// @return amount The amount earned.
    function protocolGive(uint8 idx) internal returns (uint256 amount) {
        Simplex storage simplex = Store.simplex();
        amount = simplex.protocolEarnings[idx];
        simplex.protocolEarnings[idx] = 0;
    }

    // Within this bound, valueStaked and target are effectively zero.
    function deMinimusValue() internal view returns (uint256 dM) {
        dM = uint256(Store.simplex().searchParams.deMinimusX128);
        if (uint128(dM) > 0) {
            dM = (dM >> 128) + 1;
        } else {
            dM = dM >> 128;
        }
    }

    function setE(uint8 idx, uint256 eX128) internal {
        Simplex storage s = Store.simplex();
        s.esX128[idx] = eX128;
        s.minXPerTX128[idx] = ValueLib.calcMinXPerTX128(eX128);
    }

    function getEs() internal view returns (uint256[MAX_TOKENS] storage) {
        return Store.simplex().esX128;
    }

    function bgtExchange(
        uint8 idx,
        uint256 amount
    ) internal returns (uint256 bgtEarned, uint256 unspent) {
        Simplex storage s = Store.simplex();
        if (s.bgtEx == address(0)) return (0, amount);
        address token = TokenRegLib.getToken(idx);
        uint256 spentAmount;
        (bgtEarned, spentAmount) = IBGTExchanger(s.bgtEx).exchange(
            token,
            uint128(amount) // safe cast since amount cant possibly be more than 1e30
        );
        unspent = amount - spentAmount;
    }

    /// @notice Gets the current search params.
    function getSearchParams() internal view returns (SearchParams memory) {
        Simplex storage simplex = Store.simplex();
        return simplex.searchParams;
    }

    /// @notice Sets the search params.
    function setSearchParams(SearchParams calldata params) internal {
        Simplex storage simplex = Store.simplex();
        simplex.searchParams = params;
    }
}
