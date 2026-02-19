// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBurveMultiSimplex} from "../../multi/interfaces/IBurveMultiSimplex.sol";
import {MAX_TOKENS} from "../../multi/Constants.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {FullMath} from "../../FullMath.sol";

/// @title PositionValuer
/// @notice Oracle-based multi-token position valuation for BurveLender.
///         Queries Burve closure state, converts to real amounts via adjustor,
///         then prices each token using Chainlink feeds.
library PositionValuer {
    uint256 internal constant PRICE_PRECISION = 1e8; // Chainlink USD feeds use 8 decimals
    uint256 internal constant USD_PRECISION = 1e18;  // Internal USD precision
    uint256 internal constant MAX_STALENESS = 1 hours;

    error StaleOracle(address feed);
    error InvalidOraclePrice(address feed);

    /// @notice Value a Burve position in USD.
    /// @param pool The Burve diamond address.
    /// @param closureId The closure containing the position.
    /// @param positionValue The value units owned by this position.
    /// @param positionBgtValue The BGT value units owned by this position.
    /// @param priceFeeds Mapping of token address => Chainlink price feed.
    /// @return usdValue The position value in USD (1e18 precision).
    function valuePositionUSD(
        address pool,
        uint16 closureId,
        uint256 positionValue,
        uint256 positionBgtValue,
        mapping(address => address) storage priceFeeds
    ) internal view returns (uint256 usdValue) {
        (
            uint8 n,
            ,
            uint256[MAX_TOKENS] memory balances,
            uint256 valueStaked,
        ) = IBurveMultiSimplex(pool).getClosureValue(closureId);

        if (valueStaked == 0) return 0;

        address[] memory tokens = IBurveMultiSimplex(pool).getTokens();

        uint256 totalPosition = positionValue + positionBgtValue;

        for (uint256 i = 0; i < n; i++) {
            if (balances[i] == 0) continue;

            // Calculate user's share of this token's nominal balance
            uint256 userShare = FullMath.mulDiv(balances[i], totalPosition, valueStaked);

            // Price via oracle
            uint256 tokenPrice = getPrice(priceFeeds[tokens[i]]);

            // Burve balances from getClosureValue are nominal (18-dec normalized).
            // nominalAmount * price / 1e8 = USD in 1e18
            usdValue += FullMath.mulDiv(userShare, tokenPrice, PRICE_PRECISION);
        }
    }

    /// @notice Value a specific token amount in USD.
    /// @param amount The token amount in native decimals.
    /// @param decimals The token's decimals.
    /// @param priceFeed The Chainlink price feed address.
    /// @return usdValue The USD value (1e18 precision).
    function valueTokenUSD(
        address,
        uint256 amount,
        uint8 decimals,
        address priceFeed
    ) internal view returns (uint256 usdValue) {
        uint256 price = getPrice(priceFeed);
        // amount * price * 1e18 / (1e8 * 10^decimals)
        usdValue = FullMath.mulDiv(amount, price * USD_PRECISION, PRICE_PRECISION * (10 ** decimals));
    }

    /// @notice Get the latest price from a Chainlink feed, reverting on staleness.
    /// @param feed The Chainlink AggregatorV3 address.
    /// @return price The price (8 decimal precision).
    function getPrice(address feed) internal view returns (uint256 price) {
        if (feed == address(0)) revert InvalidOraclePrice(feed);

        (
            ,
            int256 answer,
            ,
            uint256 updatedAt,
        ) = AggregatorV3Interface(feed).latestRoundData();

        if (answer <= 0) revert InvalidOraclePrice(feed);
        if (block.timestamp - updatedAt > MAX_STALENESS) revert StaleOracle(feed);

        price = uint256(answer);
    }
}
