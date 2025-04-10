// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MAX_TOKENS} from "../Token.sol";
import {SimplexLib} from "../Simplex.sol";
import {VertexId, VertexLib} from "../vertex/Id.sol";

/// Holds the information relevant to a single closure
/// @dev NOTE Closures only operate in nominal terms. Be sure to converted before interacting.
struct Closure {
    ClosureId cid; // Indicates our token set.
    uint8 n; // number of tokens in this closure
    /* Edge info */
    uint256 targetX128; // targetValue of a single token. n * target is the total value.
    uint256 baseFeeX128; // Fees charge per swap for this closure.
    /* Earnings info */
    uint256 protocolTakeX128; // Protocol's rev share of fees earned.
    /* Current asset holdings */
    uint256[MAX_TOKENS] balances; // The balances we need for swapping in this closure.
    uint128 valueStaked; // The total amount of value tokens currently earning in this closure. <= n * target.
    uint128 bgtValueStaked; // Amount of value tokens directing earnings to BGT.
    /* Earnings for the two types of value */
    // NOTE These earnings are in share value within the reserve pool, so they can continue to compound and grow.
    uint256[MAX_TOKENS] earningsPerValueX128; // The earnings checkpoint for a single non-bgt value token.
    uint256 bgtPerBgtValueX128; // BGT earnings checkpoint for bgt value tokens.
    uint256[MAX_TOKENS] unexchangedPerBgtValueX128; // Backup for when exchanges are unavailable.
}

using ClosureImpl for Closure global;

library ClosureImpl {

    /// Initialize a closure and add a small balance of each token to get it started. This balance is burned.
    function init(Closure storage self, ClosureId cid, uint256 target, uint256 baseFeeX128, uint256 protocolFee) internal {
        self.cid = cid;
        // TODO add balances and initialize value.
    }

    /// Add value to a closure by adding to every token in the closure.
    /// @dev Value added must fit in 128 bits (which every sensible balance will).
    /// @return requiredBalances The amount of each token (in nominal terms) that we need to
    function addValue(
        Closure storage self,
        uint256 value,
        uint256 bgtValue
    ) internal returns (uint256[MAX_TOKENS] requiredBalances) {
        // Round up so they add dust.
        uint256 scaleX128 = FullMath.mulDivX256(
            value,
            self.n * self.targetX128,
            true
        );
        uint256 valueX128 = value << 128;
        // Technically, by rounding up there will be a higher target value than actual value in the pool.
        // This is not an issue as it causes redeems to be less by dust and swaps to be more expensive by dust.
        // Plus this will be fixed when someone adds/removes value with an exact token amount.
        self.targetX128 +=
            valueX128 /
            self.n +
            ((valueX128 % self.n) > 0 ? 1 : 0);
        self.valueStaked += value;
        self.bgtValueStaked += bgtValue;
        // Value is handled. Now handle balances.
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            requiredBalances[i] = FullMath.mulX128(
                scaleX128,
                self.balances[i],
                true
            );
            self.balances[i] += requiredBalances[i];
        }
    }

    /// Add value to a closure by adding to a single token in the closure.
    function addValueSingle(
        Closure storage self,
        uint256 value,
        uint256 bgtValue,
        VertexId vid
    ) internal returns (uint256 requiredAmount) {
        uint256 scaleX128 = FullMath.mulDivX256(
            value,
            self.n * self.targetX128,
            true
        );
        uint256 valueX128 = value << 128;
        self.targetX128 +=
            valueX128 /
            self.n +
            ((valueX128 % self.n) > 0 ? 1 : 0);
        self.valueStaked += value;
        self.bgtValueStaked += bgtValue;
        // We first calculate what value is effectively "lost" by not adding the tokens.
        // And then we make sure to add that amount of value to the deposit token.
        uint256[MAX_TOKENS] storage esX128 = SimplexLib.getEs();
        uint256 missingValueX128 = 0;
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            uint256 requiredBalance = FullMath.mulX128(
                scaleX128,
                self.balances[i],
                true
            );
            uint256 eX128 = esX128[i];
            missingValueX128 += ValueLib.v(self.targetX128, eX128, requiredBalance + self.balances[i], true) - ValueLib.v(self.targetX128, eX128, self.balances[i], false);
        }
        // No we add the missing value.
        uint8 vIdx = vid.idx();
        uint256 eX128 = esX128[vIdx];
        uint256 currentValueX128 = ValueLib.v(self.targetX128, eX128, self.balances[vIdx], false);
        // To get the required amount.
        requiredAmount = ValueLib.x(self.targetX128, eX128, currentValueX128 + missingValueX128, true);
        self.balances[vIdx] += requiredAmount;

    }

    /// Remove value from a closure by removing from every token in the closure.
    /// Note that fee claiming is separate and should be done on the asset. This merely changes the state of the closure.
    /// @dev Value removed must fit in 128 bits (which every sensible balance will).
    /// @return withdrawnBalances The amount of each token (in nominal terms) that the remove takes out of the pool
    function removeValue(
        Closure storage self,
        uint256 value,
        uint256 bgtValue
    ) internal returns (uint256[MAX_TOKENS] withdrawnBalances) {
        // Round down to leave dust.
        uint256 scaleX128 = FullMath.mulDivX256(
            value,
            self.n * self.targetX128,
            false
        );
        uint256 valueX128 = value << 128;
        // We round down here to like addValue we keep more target value in the pool.
        self.targetX128 += valueX128 / self.n;
        self.valueStaked -= value;
        self.bgtValueStaked -= bgtValue;
        // Value is handled. Now handle balances.
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            withdrawnBalances[i] = FullMath.mulX128(
                scaleX128,
                self.balances[i],
                false
            );
            self.balances[i] -= withdrawnBalances[i];
        }
    }

    /// Remove value from a closure through a single token.
    function removeValueSingle() {}

    /// Add an exact amount of one token and receive value in return.
    function addTokenForValue() {}

    /// Remove an exact amount of one token and pay the requisite value.
    function removeTokenForValue() {}

    /// Swap in with an exact amount of one token for another.
    function swapInExact() {}

    /// Swap out an exact amount of one token by swapping in another.
    function swapOutExact() {}

    /// Stake value tokens in this closure if there is value to be redeemed.
    function stakeValue(
        Closure storage self,
        uint256 value,
        uint256 bgtValue
    ) internal {
        uint256 maxValue = (self.targetX128 * self.n) >> 128;
        require(maxValue > value, InsufficientStakeCapacity(self.cid, )
    }

    /// Remove staked value tokens from this closure. Asset checks if you have said value tokens to begin with.
    /// This doens't change the target or remove tokens. Just allows for someone use to stake now.
    function unstakeValue(uint256 value, uint256 bgtValue) {}

    /* Helpers */

    /// Add total real fees collected for a given token. Can't be more than 2**128.
    /// Called after swaps and value changes.
    /// Earnings from rehypothecation happen when we trimBalance before swaps and value changes.
    function addEarnings(
        Closure storage self,
        uint8 idx,
        uint256 earnings
    ) internal {
        // Round protocol take down.
        uint256 protocolAmount = FullMath.mulX128(
            earnings,
            self.protocolTakeX128,
            false
        );
        SimplexLib.protocolTake(idx, protocolAmount); // TODO
        uint256 userAmount = earnings - protocolAmount;
        // Round BGT take down.
        uint256 bgtExAmount = (userAmount * self.bgtValueStaked) /
            self.valueStaked;
        (uint256 bgtEarned, uint256 unspent) = SimplexLib.bgtExchange(
            idx,
            bgtExAmount
        ); // TODO
        self.bgtPerBgtValueX128 += (bgtEarned << 128) / self.bgtValueStaked;
        // We total the shares earned and split after to reduce our vault deposits, and
        // we potentially lose one less dust.
        uint256 valueAmount = userAmount - bgtExAmount;
        uint256 reserveShares = ReserveLib.deposit(idx, unspent + valueAmount);
        if (unspent > 0) {
            // rare
            uint256 unspentShares = (reserveShares * unspent) /
                (valueAmount + unspent);
            self.unexchangedPerBgtValueX128[idx] +=
                (unspentShares << 128) /
                self.bgtValueStaked;
            reserveShares -= unspentShares;
        }
        // Rest goes to non bgt value.
        self.earningsPerValueX128[idx] +=
            (reserveShares << 128) /
            (self.valueStaked - self.bgtValueStaked);
    }
}
