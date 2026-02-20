// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBurveMultiSimplex} from "../../multi/interfaces/IBurveMultiSimplex.sol";
import {MAX_TOKENS} from "../../multi/Constants.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {FullMath} from "../../FullMath.sol";

/// @title PositionValuer
/// @notice Oracle-based multi-token position valuation for the Lender.
///         Queries Burve closure state, computes pro-rata share of each token,
///         then prices each token using Chainlink feeds.
library PositionValuer {
    uint256 internal constant USD_PRECISION = 1e18;
    uint256 internal constant MAX_STALENESS = 1 hours;

    error StaleOracle(address feed);
    error InvalidOraclePrice(address feed);

    /// @notice Value a Burve position in USD.
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
            uint256 bgtValueStaked
        ) = IBurveMultiSimplex(pool).getClosureValue(closureId);

        // Fix: denominator must include BOTH valueStaked and bgtValueStaked
        uint256 totalStaked = valueStaked + bgtValueStaked;
        if (totalStaked == 0) return 0;

        address[] memory tokens = IBurveMultiSimplex(pool).getTokens();
        uint256 totalPosition = positionValue + positionBgtValue;

        for (uint256 i = 0; i < n; i++) {
            if (balances[i] == 0) continue;

            // User's pro-rata share of this token's nominal balance
            uint256 userShare = FullMath.mulDiv(balances[i], totalPosition, totalStaked);

            // Price via oracle — Burve balances are nominal (18-dec normalized)
            address feed = priceFeeds[tokens[i]];
            if (feed == address(0)) revert InvalidOraclePrice(feed);
            (uint256 price, uint8 feedDecimals) = getPrice(feed);

            // nominalAmount * price / 10^feedDecimals = USD in 1e18
            usdValue += FullMath.mulDiv(userShare, price, 10 ** feedDecimals);
        }
    }

    /// @notice Value a specific token amount in USD.
    /// @param amount The token amount in native decimals.
    /// @param decimals The token's decimals.
    /// @param priceFeed The Chainlink price feed address.
    /// @return usdValue The USD value (1e18 precision).
    function valueTokenUSD(
        uint256 amount,
        uint8 decimals,
        address priceFeed
    ) internal view returns (uint256 usdValue) {
        (uint256 price, uint8 feedDecimals) = getPrice(priceFeed);
        // amount * price * 1e18 / (10^feedDecimals * 10^decimals)
        usdValue = FullMath.mulDiv(
            amount,
            price * USD_PRECISION,
            (10 ** feedDecimals) * (10 ** decimals)
        );
    }

    /// @notice Value a Burve position in USD with per-token collateral factors.
    /// @return adjustedUSD The risk-adjusted position value in USD (1e18 precision).
    function weightedValuePositionUSD(
        address pool,
        uint16 closureId,
        uint256 positionValue,
        uint256 positionBgtValue,
        mapping(address => address) storage priceFeeds,
        mapping(address => uint256) storage _collateralFactors
    ) internal view returns (uint256 adjustedUSD) {
        (
            uint8 n,
            ,
            uint256[MAX_TOKENS] memory balances,
            uint256 valueStaked,
            uint256 bgtValueStaked
        ) = IBurveMultiSimplex(pool).getClosureValue(closureId);

        uint256 totalStaked = valueStaked + bgtValueStaked;
        if (totalStaked == 0) return 0;

        address[] memory tokens = IBurveMultiSimplex(pool).getTokens();
        uint256 totalPosition = positionValue + positionBgtValue;

        for (uint256 i = 0; i < n; i++) {
            if (balances[i] == 0) continue;

            uint256 userShare = FullMath.mulDiv(balances[i], totalPosition, totalStaked);
            address feed = priceFeeds[tokens[i]];
            if (feed == address(0)) revert InvalidOraclePrice(feed);
            (uint256 tokenPrice, uint8 feedDecimals) = getPrice(feed);
            uint256 tokenUSD = FullMath.mulDiv(userShare, tokenPrice, 10 ** feedDecimals);

            // Apply collateral factor: 0 stored means default (100%)
            uint256 factor = _collateralFactors[tokens[i]];
            if (factor == 0) factor = USD_PRECISION;
            adjustedUSD += FullMath.mulDiv(tokenUSD, factor, USD_PRECISION);
        }
    }

    /// @notice Get per-token USD values for a position (without collateral factors).
    function tokenValuesUSD(
        address pool,
        uint16 closureId,
        uint256 positionValue,
        uint256 positionBgtValue,
        mapping(address => address) storage priceFeeds
    ) internal view returns (uint256[MAX_TOKENS] memory values) {
        (
            uint8 n,
            ,
            uint256[MAX_TOKENS] memory balances,
            uint256 valueStaked,
            uint256 bgtValueStaked
        ) = IBurveMultiSimplex(pool).getClosureValue(closureId);

        uint256 totalStaked = valueStaked + bgtValueStaked;
        if (totalStaked == 0) return values;

        address[] memory tokens = IBurveMultiSimplex(pool).getTokens();
        uint256 totalPosition = positionValue + positionBgtValue;

        for (uint256 i = 0; i < n; i++) {
            if (balances[i] == 0) continue;
            uint256 userShare = FullMath.mulDiv(balances[i], totalPosition, totalStaked);
            address feed = priceFeeds[tokens[i]];
            if (feed == address(0)) continue;
            (uint256 tokenPrice, uint8 feedDecimals) = getPrice(feed);
            values[i] = FullMath.mulDiv(userShare, tokenPrice, 10 ** feedDecimals);
        }
    }

    /// @notice Convert a USD value to a token amount using oracle price.
    function usdToTokenAmount(
        uint256 usdValue,
        uint8 decimals,
        address priceFeed
    ) internal view returns (uint256 amount) {
        (uint256 price, uint8 feedDecimals) = getPrice(priceFeed);
        // amount = usdValue * 10^feedDecimals * 10^decimals / (price * 1e18)
        amount = FullMath.mulDiv(
            usdValue,
            (10 ** feedDecimals) * (10 ** decimals),
            price * USD_PRECISION
        );
    }

    /// @notice Get the latest price from a Chainlink feed, reverting on staleness.
    /// @return price The raw price value.
    /// @return feedDecimals The number of decimals in the price feed.
    function getPrice(address feed) internal view returns (uint256 price, uint8 feedDecimals) {
        if (feed == address(0)) revert InvalidOraclePrice(feed);

        (
            ,
            int256 answer,
            ,
            uint256 updatedAt,
        ) = AggregatorV3Interface(feed).latestRoundData();

        if (answer <= 0) revert InvalidOraclePrice(feed);
        // Fix: use >= for staleness check (boundary-inclusive)
        if (block.timestamp - updatedAt >= MAX_STALENESS) revert StaleOracle(feed);

        price = uint256(answer);
        // Fix: read actual decimals from feed instead of hardcoding 8
        feedDecimals = AggregatorV3Interface(feed).decimals();
    }
}
