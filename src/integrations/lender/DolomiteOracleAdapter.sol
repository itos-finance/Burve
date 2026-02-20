// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

/// @notice Minimal interface for Dolomite's price oracle (OracleAggregatorV2 or any IDolomitePriceOracle).
///         `getPrice(token)` returns a struct with a single `uint256 value` field.
///         Price precision: `36 - tokenDecimals` decimals.
///         e.g. USDC (6 dec) → 1e30 for $1, WETH (18 dec) → 2000e18 for $2000.
interface IDolomitePriceOracle {
    struct MonetaryPrice {
        uint256 value;
    }
    function getPrice(address token) external view returns (MonetaryPrice memory);
}

/// @title DolomiteOracleAdapter
/// @notice Wraps a Dolomite price oracle behind Chainlink's AggregatorV3Interface,
///         allowing BurveLender's PositionValuer to consume Dolomite prices seamlessly.
///
///         Dolomite prices have `36 - tokenDecimals` decimals of precision.
///         Chainlink USD feeds use 8 decimals.
///         This adapter converts: `chainlinkAnswer = dolomitePrice / 10^(28 - tokenDecimals)`
contract DolomiteOracleAdapter is AggregatorV3Interface {

    IDolomitePriceOracle public immutable DOLOMITE_ORACLE;
    address public immutable TOKEN;
    uint8 public immutable TOKEN_DECIMALS;

    /// @dev Scaling divisor: `10^(36 - tokenDecimals - 8)` = `10^(28 - tokenDecimals)`
    uint256 internal immutable SCALE_DIVISOR;

    uint8 public constant CHAINLINK_DECIMALS = 8;

    error InvalidTokenDecimals();
    error ZeroDolomitePrice();

    /// @param dolomiteOracle The Dolomite oracle address (e.g. OracleAggregatorV2).
    /// @param token The token whose price this adapter provides.
    /// @param tokenDecimals_ The token's ERC20 decimals (must be <= 28).
    constructor(address dolomiteOracle, address token, uint8 tokenDecimals_) {
        if (tokenDecimals_ > 28) revert InvalidTokenDecimals();

        DOLOMITE_ORACLE = IDolomitePriceOracle(dolomiteOracle);
        TOKEN = token;
        TOKEN_DECIMALS = tokenDecimals_;
        SCALE_DIVISOR = 10 ** (28 - tokenDecimals_);
    }

    /// @notice Returns 8, matching Chainlink USD feed convention.
    function decimals() external pure returns (uint8) {
        return CHAINLINK_DECIMALS;
    }

    /// @notice Fetches the Dolomite price and converts it to Chainlink format.
    /// @dev `updatedAt` is always `block.timestamp` because Dolomite prices are computed on-demand
    ///      (no push-based heartbeat). PositionValuer's staleness check is effectively a no-op for
    ///      this adapter — staleness protection relies on Dolomite's own feed validation instead.
    /// @return roundId Always 0 (Dolomite has no round concept).
    /// @return answer The price in 8-decimal Chainlink format.
    /// @return startedAt Always block.timestamp.
    /// @return updatedAt Always block.timestamp (Dolomite prices are live/on-demand).
    /// @return answeredInRound Always 0.
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        IDolomitePriceOracle.MonetaryPrice memory price = DOLOMITE_ORACLE.getPrice(TOKEN);
        if (price.value == 0) revert ZeroDolomitePrice();

        // Convert from (36 - tokenDecimals) decimals to 8 decimals
        // answer = price.value / 10^(28 - tokenDecimals)
        answer = int256(price.value / SCALE_DIVISOR);

        roundId = 0;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 0;
    }
}
