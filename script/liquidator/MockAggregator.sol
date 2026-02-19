// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/// @title MockAggregator
/// @notice Deployable mock Chainlink price feed for Anvil fork testing.
///         Owner can set price at will to simulate market conditions.
contract MockAggregator {
    int256 public price;
    uint8 public immutable oracleDecimals;
    uint256 public updatedAt;
    address public owner;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        oracleDecimals = _decimals;
        updatedAt = block.timestamp;
        owner = msg.sender;
    }

    function setPrice(int256 _price) external {
        require(msg.sender == owner, "only owner");
        price = _price;
        updatedAt = block.timestamp;
    }

    function decimals() external view returns (uint8) {
        return oracleDecimals;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 _updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, price, block.timestamp, updatedAt, 1);
    }
}
