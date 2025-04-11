// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MAX_TOKENS} from "./../Constants.sol";
import {SimplexLib} from "../Simplex.sol";
import {VertexId, VertexLib} from "../vertex/Id.sol";
import {AdjustorLib} from "../Adjustor.sol";
import {ClosureId} from "./Id.sol";
import {FullMath} from "../../FullMath.sol";
import {ValueLib} from "../Value.sol";
import {ReserveLib} from "../vertex/Reserve.sol";
import {Store} from "../Store.sol";
import {UnsafeMath} from "Commons/Math/UnsafeMath.sol";

/// Holds the information relevant to a single closure
/// @dev NOTE Closures operate in nominal terms. Be sure to converted before interacting.
/// @dev It does convert to real when interacting with Vertex in trimming though.
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
    // TODO: remove after fixing below
    error NotImplemented();

    uint256 public constant ONEX128 = 1 << 128;
    event WarningExcessValueDetected(
        ClosureId cid,
        uint256 maxValue,
        uint256 actualValue
    );
    error InsufficientStakeCapacity(
        ClosureId cid,
        uint256 maxValue,
        uint256 actualValue,
        uint256 attemptedStake
    );
    error InsufficientUnstakeAvailable(
        ClosureId cid,
        uint256 stakeValue,
        uint256 attemptedUnstake
    );
    error IrrelevantVertex(ClosureId cid, VertexId vid);

    /// Initialize a closure and add a small balance of each token to get it started. This balance is burned.
    function init(
        Closure storage self,
        ClosureId cid,
        uint256 target,
        uint256 baseFeeX128,
        uint256 protocolTakeX128
    ) internal returns (uint256[MAX_TOKENS] storage balancesNeeded) {
        self.cid = cid;
        self.targetX128 = target << 128;
        self.baseFeeX128 = baseFeeX128;
        self.protocolTakeX128 = protocolTakeX128;
        for (VertexId vIter = VertexLib.minId(); !vIter.isStop(); vIter.inc()) {
            if (cid.contains(vIter)) {
                self.n += 1;
                self.balances[vIter.idx()] += target;
            }
        }
        // Tiny burned value.
        // TODO: fix cast. Changed to compile
        self.valueStaked += uint128(target * self.n);
        return self.balances;
    }

    /// Add value to a closure by adding to every token in the closure.
    /// @dev Value added must fit in 128 bits (which every sensible balance will).
    /// @return requiredBalances The amount of each token (in nominal terms) that we need to
    function addValue(
        Closure storage self,
        uint256 value,
        uint256 bgtValue
    ) internal returns (uint256[MAX_TOKENS] memory requiredBalances) {
        trimAllBalances(self);
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
        // TODO: fix cast. Changed to compile
        self.valueStaked += uint128(value);
        // TODO: fix cast. Changed to compile
        self.bgtValueStaked += uint128(bgtValue);
        // Value is handled. Now handle balances.
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            requiredBalances[i] = FullMath.mulX128(
                scaleX128,
                self.balances[i],
                true
            );
            // This happens after because the vault will have
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
        revert NotImplemented();
    }

    // TODO: fix. Hitting stack too deep on compile error.
    // function addValueSingle(
    //     Closure storage self,
    //     uint256 value,
    //     uint256 bgtValue,
    //     VertexId vid
    // ) internal returns (uint256 requiredAmount) {
    //     require(self.cid.contains(vid), IrrelevantVertex(self.cid, vid));
    //     // We still need to trim all balances here because value is changing.
    //     trimAllBalances(self);
    //     uint256 scaleX128 = FullMath.mulDivX256(
    //         value,
    //         self.n * self.targetX128,
    //         true
    //     );
    //     uint256 valueX128 = value << 128;
    //     self.targetX128 +=
    //         valueX128 /
    //         self.n +
    //         ((valueX128 % self.n) > 0 ? 1 : 0);
    //     // We first calculate what value is effectively "lost" by not adding the tokens.
    //     // And then we make sure to add that amount of value to the deposit token.
    //     uint8 vIdx = vid.idx();
    //     uint256[MAX_TOKENS] storage esX128 = SimplexLib.getEs();
    //     uint256 missingValueX128 = 0;
    //     for (uint8 i = 0; i < MAX_TOKENS; ++i) {
    //         if (self.balances[i] == 0) continue;

    //         uint256 requiredBalance = FullMath.mulX128(
    //             scaleX128,
    //             self.balances[i],
    //             true
    //         );
    //         if (i == vIdx) {
    //             // the amount added to the in token is not taxed.
    //             requiredAmount = requiredBalance;
    //             self.balances[i] += requiredBalance;
    //             // And there is no missing value here.
    //             continue;
    //         }
    //         // For all other tokens, we have to add the missing value.
    //         uint256 eX128 = esX128[i];
    //         missingValueX128 +=
    //             ValueLib.v(
    //                 self.targetX128,
    //                 eX128,
    //                 requiredBalance + self.balances[i],
    //                 true
    //             ) -
    //             ValueLib.v(self.targetX128, eX128, self.balances[i], false);
    //     }
    //     // Now we add the missing value.
    //     uint256 veX128 = esX128[vIdx];
    //     uint256 currentValueX128 = ValueLib.v(
    //         self.targetX128,
    //         veX128,
    //         self.balances[vIdx],
    //         false
    //     );
    //     // To get the required amount.
    //     uint256 finalAmount = ValueLib.x(
    //         self.targetX128,
    //         veX128,
    //         currentValueX128 + missingValueX128,
    //         true
    //     );
    //     uint256 untaxedRequired = finalAmount - self.balances[vIdx];
    //     self.balances[vIdx] = finalAmount;
    //     uint256 taxedRequired = UnsafeMath.divRoundingUp(
    //         untaxedRequired << 128,
    //         ONEX128 - self.baseFeeX128
    //     );
    //     addEarnings(self, vIdx, taxedRequired - untaxedRequired);
    //     requiredAmount += taxedRequired;
    //     // This needs to happen after any fee earnings.
    //     // TODO: fix cast. Changed to compile
    //     self.valueStaked += uint128(value);
    //     // TODO: fix cast. Changed to compile
    //     self.bgtValueStaked += uint128(bgtValue);
    // }

    /// Remove value from a closure by removing from every token in the closure.
    /// Note that fee claiming is separate and should be done on the asset. This merely changes the closure.
    /// @dev Value removed must fit in 128 bits (which every sensible balance will).
    /// @return withdrawnBalances The amount of each token (in nominal terms) that the remove takes out of the pool
    function removeValue(
        Closure storage self,
        uint256 value,
        uint256 bgtValue
    ) internal returns (uint256[MAX_TOKENS] memory withdrawnBalances) {
        trimAllBalances(self);
        // Round down to leave dust.
        uint256 scaleX128 = FullMath.mulDivX256(
            value,
            self.n * self.targetX128,
            false
        );
        uint256 valueX128 = value << 128;
        // We round down here to like addValue we keep more target value in the pool.
        self.targetX128 += valueX128 / self.n;
        // TODO: fix cast. Changed to compile
        self.valueStaked -= uint128(value);
        // TODO: fix cast. Changed to compile
        self.bgtValueStaked -= uint128(bgtValue);
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
    function removeValueSingle(
        Closure storage self,
        uint256 value,
        uint256 bgtValue,
        VertexId vid
    ) internal returns (uint256 removedAmount) {
        require(self.cid.contains(vid), IrrelevantVertex(self.cid, vid));
        trimAllBalances(self);
        uint256 scaleX128 = FullMath.mulDivX256(
            value,
            self.n * self.targetX128,
            true
        );
        uint256 valueX128 = value << 128;
        // Round leftover value up.
        self.targetX128 -= valueX128 / self.n;
        // We first calculate what value is effectively "added" by not removing the tokens.
        // And then we make sure to remove that amount of value with the out token.
        uint8 vIdx = vid.idx();
        uint256[MAX_TOKENS] storage esX128 = SimplexLib.getEs();
        uint256 addedValueX128 = 0;
        for (uint8 i = 0; i < MAX_TOKENS; ++i) {
            if (self.balances[i] == 0) continue;

            // Round this down to round down the "added" value.
            uint256 scaledBalance = FullMath.mulX128(
                scaleX128,
                self.balances[i],
                false
            );
            if (i == vIdx) {
                // the amount removed from the out token is not taxed.
                removedAmount = scaledBalance;
                self.balances[i] -= scaledBalance;
                continue;
            }

            uint256 eX128 = esX128[i];
            addedValueX128 +=
                ValueLib.v(self.targetX128, eX128, self.balances[i], false) -
                ValueLib.v(
                    self.targetX128,
                    eX128,
                    self.balances[i] - scaledBalance,
                    true
                );
        }
        uint256 veX128 = esX128[vIdx];
        uint256 currentValueX128 = ValueLib.v(
            self.targetX128,
            veX128,
            self.balances[vIdx],
            false
        );
        // How much can we remove?
        uint256 finalAmount = ValueLib.x(
            self.targetX128,
            veX128,
            currentValueX128 - addedValueX128,
            true
        );
        uint256 untaxedRemove = self.balances[vIdx] - finalAmount;
        self.balances[vIdx] = finalAmount;
        uint256 tax = FullMath.mulX128(untaxedRemove, self.baseFeeX128, false); // TODO: double check rounding up
        addEarnings(self, vIdx, tax);
        removedAmount += untaxedRemove - tax;
        // This needs to happen last.
        // TODO: fix cast. Changed to compile
        self.valueStaked -= uint128(value);
        // TODO: fix cast. Changed to compile
        self.bgtValueStaked -= uint128(bgtValue);
    }

    /// Add an exact amount of one token and receive value in return.
    function addTokenForValue(
        Closure storage self,
        VertexId vid,
        uint256 amount,
        uint256 bgtPercentX256
    ) internal returns (uint256 value, uint256 bgtValue) {
        require(self.cid.contains(vid), IrrelevantVertex(self.cid, vid));
        trimAllBalances(self);
        uint8 idx = vid.idx();
        // For simplicity, we tax the entire amount in first. This overcharges slightly but an exact solution
        // would overcomplicate the contract and any approximation is game-able.
        uint256 tax = FullMath.mulX128(amount, self.baseFeeX128, true);
        addEarnings(self, idx, tax);
        amount -= tax;
        // Use the ValueLib's newton's method to solve for the value added and update target.
        uint256[MAX_TOKENS] storage esX128 = SimplexLib.getEs();
        self.balances[idx] += amount;
        uint256 newTargetX128 = ValueLib.t(
            self.n,
            esX128,
            self.balances,
            self.targetX128
        );
        // The pool is now entirely correct by just updating the target and value balances.
        value = ((newTargetX128 - self.targetX128) * self.n) >> 128; // Round down received value balance.
        bgtValue = FullMath.mulX256(value, bgtPercentX256, false); // Convention to round BGT down.
        self.targetX128 = newTargetX128;
        // TODO: fix cast. Changed to compile
        self.valueStaked += uint128(value);
        // TODO: fix cast. Changed to compile
        self.bgtValueStaked += uint128(bgtValue);
    }

    /// Remove an exact amount of one token and pay the requisite value.
    function removeTokenForValue(
        Closure storage self,
        VertexId vid,
        uint256 amount,
        uint256 bgtPercentX256
    ) internal returns (uint256 value, uint256 bgtValue) {
        require(self.cid.contains(vid), IrrelevantVertex(self.cid, vid));
        trimAllBalances(self);
        uint8 idx = vid.idx();
        // We tax first so the amount which moves up the value they're paying.
        uint256 tax = FullMath.mulX128(amount, self.baseFeeX128, true);
        addEarnings(self, idx, tax);
        amount += tax;
        // Use the ValueLib's newton's method to solve for the value removed and update target.
        uint256[MAX_TOKENS] storage esX128 = SimplexLib.getEs();
        self.balances[idx] -= amount;
        uint256 newTargetX128 = ValueLib.t(
            self.n,
            esX128,
            self.balances,
            self.targetX128 // TODO: Estimate a better starting guess.
        );
        // The pool is now entirely correct by just updating the target and value balances.
        uint256 valueX128 = ((self.targetX128 - newTargetX128) * self.n);
        value = valueX128 >> 128;
        if ((value << 128) > 0) value += 1; // We need to round up.
        bgtValue = FullMath.mulX256(value, bgtPercentX256, false); // Convention to round BGT down both ways.
        self.targetX128 = newTargetX128;
        // TODO: fix cast. Changed to compile
        self.valueStaked -= uint128(value);
        // TODO: fix cast. Changed to compile
        self.bgtValueStaked -= uint128(bgtValue);
    }

    /// Swap in with an exact amount of one token for another.
    /// Convention is to always take fees from the in token.
    function swapInExact(
        Closure storage self,
        VertexId inVid,
        VertexId outVid,
        uint256 inAmount
    ) internal returns (uint256 outAmount) {
        require(self.cid.contains(inVid), IrrelevantVertex(self.cid, inVid));
        require(self.cid.contains(outVid), IrrelevantVertex(self.cid, outVid));
        trimBalance(self, inVid);
        trimBalance(self, outVid);
        // The value in this pool won't change.
        uint256[MAX_TOKENS] storage esX128 = SimplexLib.getEs();
        // First tax the in token.
        uint8 inIdx = inVid.idx();
        uint256 tax = FullMath.mulX128(inAmount, self.baseFeeX128, true);
        addEarnings(self, inIdx, tax);
        inAmount -= tax;
        // Calculate the value added by the in token.
        uint256 valueAddedX128 = ValueLib.v(
            self.targetX128,
            esX128[inIdx],
            self.balances[inIdx] + inAmount,
            false
        ) -
            ValueLib.v(
                self.targetX128,
                esX128[inIdx],
                self.balances[inIdx],
                true
            );
        self.balances[inIdx] += inAmount;
        uint8 outIdx = outVid.idx();
        // To round down the out amount, we want to remove value at lower values on the curve.
        // But we want to round up the newOutBalance which means we want a higher newOutValue.
        // Ultimately these are both valid and both negligible, so it doesn't matter.
        uint256 currentOutValueX128 = ValueLib.v(
            self.targetX128,
            esX128[outIdx],
            self.balances[outIdx],
            true
        );
        uint256 newOutValueX128 = currentOutValueX128 - valueAddedX128;
        uint256 newOutBalance = ValueLib.x(
            self.targetX128,
            esX128[outIdx],
            newOutValueX128,
            true
        );
        outAmount = self.balances[outIdx] - newOutBalance;
        self.balances[outIdx] = newOutBalance;
    }

    /// Swap out an exact amount of one token by swapping in another.
    /// We have to take fees from the in-token.
    function swapOutExact(
        Closure storage self,
        VertexId inVid,
        VertexId outVid,
        uint256 outAmount
    ) internal returns (uint256 inAmount) {
        require(self.cid.contains(inVid), IrrelevantVertex(self.cid, inVid));
        require(self.cid.contains(outVid), IrrelevantVertex(self.cid, outVid));
        trimBalance(self, inVid);
        trimBalance(self, outVid);
        // The value in this pool won't change.
        uint256[MAX_TOKENS] storage esX128 = SimplexLib.getEs();
        uint8 inIdx = inVid.idx();
        uint8 outIdx = outVid.idx();
        // Calculate the value removed by the out token.
        uint256 valueRemovedX128 = ValueLib.v(
            self.targetX128,
            esX128[outIdx],
            self.balances[outIdx],
            true
        ) -
            ValueLib.v(
                self.targetX128,
                esX128[outIdx],
                self.balances[outIdx] - outAmount,
                false
            );
        self.balances[outIdx] -= outAmount;
        // To round up the in amount, we want to add value at higher values on the curve.
        // But we want to round down the newInBalance which means we want a lower newInValue.
        // Ultimately these are both valid and both negligible, so it doesn't matter.
        uint256 currentInValueX128 = ValueLib.v(
            self.targetX128,
            esX128[inIdx],
            self.balances[inIdx],
            false
        );
        uint256 newInValueX128 = currentInValueX128 + valueRemovedX128;
        uint256 newInBalance = ValueLib.x(
            self.targetX128,
            esX128[inIdx],
            newInValueX128,
            false
        );
        uint256 untaxedInAmount = newInBalance - self.balances[inIdx];
        self.balances[inIdx] = newInBalance;
        // Finally we tax the in amount.
        inAmount = UnsafeMath.divRoundingUp(
            untaxedInAmount << 128,
            ONEX128 - self.baseFeeX128
        );
        addEarnings(self, inIdx, inAmount - untaxedInAmount);
    }

    /// Stake value tokens in this closure if there is value to be redeemed.
    function stakeValue(
        Closure storage self,
        uint256 value,
        uint256 bgtValue
    ) internal {
        trimAllBalances(self);
        uint256 maxValue = (self.targetX128 * self.n) >> 128;
        if (self.valueStaked > maxValue + SimplexLib.deMinimusValue())
            emit WarningExcessValueDetected(
                self.cid,
                maxValue,
                self.valueStaked
            );
        if (self.valueStaked + value > maxValue)
            revert InsufficientStakeCapacity(
                self.cid,
                maxValue,
                self.valueStaked,
                value
            );

        // TODO: fix cast. Changed to compile
        self.valueStaked += uint128(value);
        // TODO: fix cast. Changed to compile
        self.bgtValueStaked += uint128(bgtValue);
    }

    /// Simulate swapping in with an exact amount of one token for another.
    function simSwapInExact(
        Closure storage self,
        VertexId inVid,
        VertexId outVid,
        uint256 inAmount
    ) internal view returns (uint256 outAmount) {
        // The value in this pool won't change.
        uint256[MAX_TOKENS] storage esX128 = SimplexLib.getEs();
        // First tax the in token.
        uint8 inIdx = inVid.idx();
        uint256 tax = FullMath.mulX128(inAmount, self.baseFeeX128, true);
        inAmount -= tax;
        // Calculate the value added by the in token.
        uint256 valueAddedX128 = ValueLib.v(
            self.targetX128,
            esX128[inIdx],
            self.balances[inIdx] + inAmount,
            false
        ) -
            ValueLib.v(
                self.targetX128,
                esX128[inIdx],
                self.balances[inIdx],
                true
            );
        uint8 outIdx = outVid.idx();
        // To round down the out amount, we want to remove value at lower values on the curve.
        // But we want to round up the newOutBalance which means we want a higher newOutValue.
        // Ultimately these are both valid and both negligible, so it doesn't matter.
        uint256 currentOutValueX128 = ValueLib.v(
            self.targetX128,
            esX128[outIdx],
            self.balances[outIdx],
            true
        );
        uint256 newOutValueX128 = currentOutValueX128 - valueAddedX128;
        uint256 newOutBalance = ValueLib.x(
            self.targetX128,
            esX128[outIdx],
            newOutValueX128,
            true
        );
        outAmount = self.balances[outIdx] - newOutBalance;
    }

    /// Simulate swaping out an exact amount of one token by swapping in another.
    function simSwapOutExact(
        Closure storage self,
        VertexId inVid,
        VertexId outVid,
        uint256 outAmount
    ) internal view returns (uint256 inAmount) {
        uint256[MAX_TOKENS] storage esX128 = SimplexLib.getEs();
        uint8 inIdx = inVid.idx();
        uint8 outIdx = outVid.idx();
        // Calculate the value removed by the out token.
        uint256 valueRemovedX128 = ValueLib.v(
            self.targetX128,
            esX128[outIdx],
            self.balances[outIdx],
            true
        ) -
            ValueLib.v(
                self.targetX128,
                esX128[outIdx],
                self.balances[outIdx] - outAmount,
                false
            );
        // To round up the in amount, we want to add value at higher values on the curve.
        // But we want to round down the newInBalance which means we want a lower newInValue.
        // Ultimately these are both valid and both negligible, so it doesn't matter.
        uint256 currentInValueX128 = ValueLib.v(
            self.targetX128,
            esX128[inIdx],
            self.balances[inIdx],
            false
        );
        uint256 newInValueX128 = currentInValueX128 + valueRemovedX128;
        uint256 newInBalance = ValueLib.x(
            self.targetX128,
            esX128[inIdx],
            newInValueX128,
            false
        );
        uint256 untaxedInAmount = newInBalance - self.balances[inIdx];
        // Finally we tax the in amount.
        inAmount = UnsafeMath.divRoundingUp(
            untaxedInAmount << 128,
            ONEX128 - self.baseFeeX128
        );
    }

    /// Remove staked value tokens from this closure. Asset checks if you have said value tokens to begin with.
    /// This doens't change the target or remove tokens. Just allows for someone use to stake now.
    function unstakeValue(
        Closure storage self,
        uint256 value,
        uint256 bgtValue
    ) internal {
        trimAllBalances(self);
        // Unstakers can't remove more than deminimus.
        if (self.valueStaked - SimplexLib.deMinimusValue() < value)
            revert InsufficientUnstakeAvailable(
                self.cid,
                self.valueStaked,
                value
            );
        // TODO: fix cast. Changed to compile
        self.valueStaked -= uint128(value);
        // TODO: fix cast. Changed to compile
        self.bgtValueStaked -= uint128(bgtValue);
    }

    /// Return the current fee checkpoints.
    function getCheck(
        Closure storage self
    )
        internal
        view
        returns (
            uint256[MAX_TOKENS] storage earningsPerValueX128,
            uint256 bgtPerBgtValueX128,
            uint256[MAX_TOKENS] storage unexchangedPerBgtValueX128
        )
    {
        return (
            self.earningsPerValueX128,
            self.bgtPerBgtValueX128,
            self.unexchangedPerBgtValueX128
        );
    }

    /* Fee Helpers */

    /// Add NOMINAL fees collected for a given token. Can't be more than 2**128.
    /// Called after swaps and value changes.
    /// Earnings from rehypothecation happen when we trimBalance before swaps and value changes.
    function addEarnings(
        Closure storage self,
        uint8 idx,
        uint256 earnings
    ) internal {
        // Earnings are given by the closure operations so they're in nominal value, but everything below
        // acts on real values so we immediately convert.
        earnings = AdjustorLib.toReal(idx, earnings, false);
        // Round protocol take down.
        uint256 protocolAmount = FullMath.mulX128(
            earnings,
            self.protocolTakeX128,
            false
        );
        SimplexLib.protocolTake(idx, protocolAmount);
        uint256 userAmount = earnings - protocolAmount;
        // Round BGT take down.
        uint256 bgtExAmount = (userAmount * self.bgtValueStaked) /
            self.valueStaked;
        (uint256 bgtEarned, uint256 unspent) = SimplexLib.bgtExchange(
            idx,
            bgtExAmount
        );
        self.bgtPerBgtValueX128 += (bgtEarned << 128) / self.bgtValueStaked;
        // We total the shares earned and split after to reduce our vault deposits, and
        // we potentially lose one less dust.
        uint256 valueAmount = userAmount - bgtExAmount;
        uint256 reserveShares = ReserveLib.deposit(
            VertexLib.newId(idx),
            unspent + valueAmount
        );
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

    /// Update the bgt earnings with the current staking balances.
    /// Called before any value changes or swaps.
    function trimAllBalances(Closure storage self) internal {
        uint256 nonBgtValueStaked = self.valueStaked - self.bgtValueStaked;
        for (VertexId vIter = VertexLib.minId(); !vIter.isStop(); vIter.inc()) {
            _trimBalance(self, vIter, nonBgtValueStaked);
        }
    }

    /// Update the bgt earnings for a single token using the current staking balances.
    function trimBalance(Closure storage self, VertexId vid) internal {
        uint256 nonBgtValueStaked = self.valueStaked - self.bgtValueStaked;
        _trimBalance(self, vid, nonBgtValueStaked);
    }

    function _trimBalance(
        Closure storage self,
        VertexId vid,
        uint256 nonBgtValueStaked
    ) private {
        uint8 idx = vid.idx();
        // Roundup the balance we need.
        uint256 realBalance = AdjustorLib.toReal(idx, self.balances[idx], true);
        (uint256 earnings, uint256 bgtReal) = Store.vertex(vid).trimBalance(
            self.cid,
            realBalance,
            self.valueStaked,
            self.bgtValueStaked
        );
        self.earningsPerValueX128[idx] += (earnings << 128) / nonBgtValueStaked;
        (uint256 bgtEarned, uint256 unspent) = SimplexLib.bgtExchange(
            idx,
            bgtReal
        );
        self.bgtPerBgtValueX128 += (bgtEarned << 128) / self.bgtValueStaked;
        // rare
        if (unspent > 0) {
            uint256 unspentShares = ReserveLib.deposit(vid, unspent);
            self.unexchangedPerBgtValueX128[idx] +=
                (unspentShares << 128) /
                self.bgtValueStaked;
        }
    }
}
