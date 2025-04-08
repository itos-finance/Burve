// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MAX_TOKENS} from "../Token.sol";

/// Holds the information relevant to a single closure
struct Closure {
    ClosureId cid; // Indicates our token set.
    uint8 n; // number of tokens in this closure
    uint256 valueX128; // targetValue of a single token. n * value is the total value.
    uint256 valueStakedX128; // The amount of value tokens in this closure.
    uint256[MAX_TOKENS] earningsPerValueX128; // The earnings checkpoint for a single value token.
}

using ClosureImpl for Closure global;

library ClosureImpl {
    /// Add total fees collected for a given token. Can't be more than 2**128 but that's probably safe.
    function addEarnings(
        Closure storage self,
        uint8 idx,
        uint128 earnings
    ) internal {
        self.earningsPerValueX128[idx] += (earnings << 128) / self.valueStaked;
    }

    /// Add value to all tokens in this closure.
    /// This doesn't actually add or remove any tokens. It just changes the target values.
    function addValue(Closure storage self, uint256 value) internal {
        self.value += value;
    }

    /// Remove value from all tokens in this closure.
    /// This doesn't remove any tokens. A later deposit/withdrawal is needed.
    /// Someone calls this first, to indicate they're removing a position and receive value tokens
    function removeValue(Closure storage self, uint256 value) internal {
        self.value -= value;
    }

    /// Add liquidity to this closure by adding tokens and getting the corresponding liquidity change.
    /// @dev Internally, the add liq pretends there is an even increase in value everywhere and then
    /// the user's actual change is treated like individual swaps.
    /// @param balanceChanges The token changes we're making. The balances not in our token set are ignored.
    function addLiqBalances(
        Closure storage self,
        uint256 value,
        uint256[MAX_TOKENS] memory balanceChanges
    ) internal {
        uint256[MAX_TOKENS] memory currentBalances = Store
            .simplex()
            .getBalances();
        uint256[MAX_TOKENS] memory targetBalances;

        self.value += value; // Each token's value has gone up by this much.
        self.valueStaked += self.n * value; // The total staked value increases accordingly.
    }

    /// Add an exactly amount of liquidity and request the necessary amount of a single token to make it happen.
    function addLiqExact(
        Closure storage self,
        uint256 addValue,
        uint8 idx
    ) internal returns (uint256 amountIn) {
        uint256[MAX_TOKENS] memory currentValues = Store
            .simplex()
            .getValues();
        // We pretend to add tokens everywhere, and then the adder swapped out some tokens.
        VertexId addVid = VertexLib.newId(idx);
        uint256 valueNeeded = 0;
        for (VertexIter vit = VertexLib.newIter(); !vit.stop(); vit.inc()) {
            if (vit.vid.isEq(addVid)) {
                continue;
            }
            if (self.cid.contains(vit.vid)) {
                uint256 balance = currentBalances[vit.idx];
                valueNeeded += EdgeLib.swapInAmount(vit.idx, balance + addValue, balance, self.value); // We added value, then removed it.
            }
        }
        EdgeLib.
    }
}
