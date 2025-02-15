// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IUniswapV3Pool} from "../../src/single/integrations/kodiak/IUniswapV3Pool.sol";

contract MockUniswapV3Pool is IUniswapV3Pool {
    error NotImplemented();

    function factory() external pure returns (address) {
        revert NotImplemented();
    }
    function token0() external pure returns (address) {
        revert NotImplemented();
    }
    function token1() external pure returns (address) {
        revert NotImplemented();
    }
    function fee() external pure returns (uint24) {
        revert NotImplemented();
    }
    function tickSpacing() external pure returns (int24) {
        revert NotImplemented();
    }
    function maxLiquidityPerTick() external pure returns (uint128) {
        revert NotImplemented();
    }
    function slot0()
        external
        pure
        returns (uint160, int24, uint16, uint16, uint16, uint32, bool)
    {
        revert NotImplemented();
    }
    function feeGrowthGlobal0X128() external pure returns (uint256) {
        revert NotImplemented();
    }
    function feeGrowthGlobal1X128() external pure returns (uint256) {
        revert NotImplemented();
    }
    function protocolFees() external pure returns (uint128, uint128) {
        revert NotImplemented();
    }
    function liquidity() external pure returns (uint128) {
        revert NotImplemented();
    }
    function ticks(
        int24
    )
        external
        pure
        returns (
            uint128,
            int128,
            uint256,
            uint256,
            int56,
            uint160,
            uint32,
            bool
        )
    {
        revert NotImplemented();
    }
    function tickBitmap(int16) external pure returns (uint256) {
        revert NotImplemented();
    }
    function positions(
        bytes32
    ) external pure returns (uint128, uint256, uint256, uint128, uint128) {
        revert NotImplemented();
    }
    function observations(
        uint256
    ) external pure returns (uint32, int56, uint160, bool) {
        revert NotImplemented();
    }
    function observe(
        uint32[] calldata
    ) external pure returns (int56[] memory, uint160[] memory) {
        revert NotImplemented();
    }
    function snapshotCumulativesInside(
        int24,
        int24
    ) external pure returns (int56, uint160, uint32) {
        revert NotImplemented();
    }
    function initialize(uint160) external pure {
        revert NotImplemented();
    }
    function mint(
        address,
        int24,
        int24,
        uint128,
        bytes calldata
    ) external pure returns (uint256, uint256) {
        revert NotImplemented();
    }
    function collect(
        address,
        int24,
        int24,
        uint128,
        uint128
    ) external pure returns (uint128, uint128) {
        revert NotImplemented();
    }
    function burn(
        int24,
        int24,
        uint128
    ) external pure returns (uint256, uint256) {
        revert NotImplemented();
    }
    function swap(
        address,
        bool,
        int256,
        uint160,
        bytes calldata
    ) external pure returns (int256, int256) {
        revert NotImplemented();
    }
    function flash(address, uint256, uint256, bytes calldata) external pure {
        revert NotImplemented();
    }
    function increaseObservationCardinalityNext(uint16) external pure {
        revert NotImplemented();
    }
    function setFeeProtocol(uint32, uint32) external pure {
        revert NotImplemented();
    }
    function collectProtocol(
        address,
        uint128,
        uint128
    ) external pure returns (uint128, uint128) {
        revert NotImplemented();
    }
}
