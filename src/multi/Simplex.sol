// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MAX_TOKENS} from "./Constants.sol";
import {IBGTExchanger} from "../integrations/BGTExchange/IBGTExchanger.sol";
import {TokenRegLib} from "./Token.sol";
import {Store} from "./Store.sol";

// Stores information unchanged between all closures.
struct Simplex {
    address adjustor;
    address bgtEx;
    /// New closures are made with at least this much target value.
    uint256 initTarget;
    /// fudge factor for value.
    uint256 deMinimusVX128;
    /// The efficiency factor for each token.
    uint256[MAX_TOKENS] esX128;
    /// Amounts earned by the protocol for withdrawal.
    uint256[MAX_TOKENS] protocolEarnings;
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

    function init(address adjustor) internal {
        Simplex storage s = Store.simplex();
        s.adjustor = adjustor;
        s.initTarget = 1e18; // reasonable default
        s.deMinimusVX128 = 1e6; // reasonable default
        // Default to 10x efficient: price range is [0.84, 1.21].
        for (uint256 i = 0; i < MAX_TOKENS; ++i) {
            s.esX128[i] = 10;
        }
    }

    function protocolTake(uint8 idx, uint256 amount) internal {
        Simplex storage s = Store.simplex();
        s.protocolEarnings[idx] += amount;
    }

    // Within this bound, valueStaked and target are effectively zero.
    function deMinimusValue() internal returns (uint256 dX128) {
        return Store.simplex().deMinimusVX128;
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
        // TODO: fix uint256 uint128 cast
        (bgtEarned, spentAmount) = IBGTExchanger(s.bgtEx).exchange(
            token,
            uint128(amount)
        );
        unspent = amount - spentAmount;
    }
}
