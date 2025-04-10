// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MAX_TOKENS} from "./Token.sol";

// Stores information unchanged between all closures.
struct Simplex {
    /// The efficiency factor for each token.
    uint256[MAX_TOKENS] esX128;
}

/// Convenient methods frequently requested by other parts of the pool.
library SimplexLib {}
