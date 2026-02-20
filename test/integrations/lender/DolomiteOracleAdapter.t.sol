// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {DolomiteOracleAdapter, IDolomitePriceOracle} from "../../../src/integrations/lender/DolomiteOracleAdapter.sol";

/// @notice Mock Dolomite oracle for testing.
contract MockDolomiteOracle is IDolomitePriceOracle {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 value) external {
        prices[token] = value;
    }

    function getPrice(address token) external view returns (MonetaryPrice memory) {
        return MonetaryPrice(prices[token]);
    }
}

contract TestDolomiteOracleAdapter is Test {
    MockDolomiteOracle public oracle;

    address constant USDC = address(0x1);
    address constant WETH = address(0x2);
    address constant WBTC = address(0x3);

    function setUp() public {
        oracle = new MockDolomiteOracle();
    }

    /// @notice USDC (6 dec): Dolomite price 1e30 ($1.00) → Chainlink 1e8
    function testUSDCPrice() public {
        DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
            address(oracle), USDC, 6
        );

        // $1.00 USDC: dolomitePrice = 1e30 (36-6=30 decimals)
        oracle.setPrice(USDC, 1e30);

        (, int256 answer,,,) = adapter.latestRoundData();
        // 1e30 / 10^(28-6) = 1e30 / 1e22 = 1e8
        assertEq(answer, int256(1e8), "USDC $1.00 should be 1e8 in Chainlink format");
    }

    /// @notice WETH (18 dec): Dolomite price 2000e18 ($2000) → Chainlink 2000e8
    function testWETHPrice() public {
        DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
            address(oracle), WETH, 18
        );

        // $2000 WETH: dolomitePrice = 2000e18 (36-18=18 decimals)
        oracle.setPrice(WETH, 2000e18);

        (, int256 answer,,,) = adapter.latestRoundData();
        // 2000e18 / 10^(28-18) = 2000e18 / 1e10 = 2000e8
        assertEq(answer, int256(2000e8), "WETH $2000 should be 2000e8");
    }

    /// @notice WBTC (8 dec): Dolomite price 60000e28 ($60000) → Chainlink 60000e8
    function testWBTCPrice() public {
        DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
            address(oracle), WBTC, 8
        );

        // $60000 WBTC: dolomitePrice = 60000e28 (36-8=28 decimals)
        oracle.setPrice(WBTC, 60000e28);

        (, int256 answer,,,) = adapter.latestRoundData();
        // 60000e28 / 10^(28-8) = 60000e28 / 1e20 = 60000e8
        assertEq(answer, int256(60000e8), "WBTC $60000 should be 60000e8");
    }

    /// @notice decimals() should return 8.
    function testDecimals() public {
        DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
            address(oracle), USDC, 6
        );
        assertEq(adapter.decimals(), 8);
    }

    /// @notice updatedAt should be block.timestamp (Dolomite prices are live).
    function testTimestamps() public {
        DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
            address(oracle), USDC, 6
        );
        oracle.setPrice(USDC, 1e30);

        (,, uint256 startedAt, uint256 updatedAt,) = adapter.latestRoundData();
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
    }

    /// @notice Fractional price: USDC at $0.997 → Dolomite 997e27, Chainlink 99700000
    function testFractionalPrice() public {
        DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
            address(oracle), USDC, 6
        );

        // $0.997: dolomitePrice = 0.997e30 = 997e27
        oracle.setPrice(USDC, 997e27);

        (, int256 answer,,,) = adapter.latestRoundData();
        // 997e27 / 1e22 = 997e5 = 99700000
        assertEq(answer, int256(99700000), "USDC $0.997 should be 99700000");
    }

    /// @notice Constructor reverts when tokenDecimals > 28.
    function testRevertsOnInvalidDecimals() public {
        vm.expectRevert(DolomiteOracleAdapter.InvalidTokenDecimals.selector);
        new DolomiteOracleAdapter(address(oracle), USDC, 29);
    }

    /// @notice Immutable getters return correct values.
    function testImmutables() public {
        DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
            address(oracle), WETH, 18
        );
        assertEq(address(adapter.DOLOMITE_ORACLE()), address(oracle));
        assertEq(adapter.TOKEN(), WETH);
        assertEq(adapter.TOKEN_DECIMALS(), 18);
    }

    /// @notice High price: WETH at $100,000
    function testHighPrice() public {
        DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
            address(oracle), WETH, 18
        );

        // $100,000: dolomitePrice = 100_000e18
        oracle.setPrice(WETH, 100_000e18);

        (, int256 answer,,,) = adapter.latestRoundData();
        assertEq(answer, int256(100_000e8), "WETH $100k should be 100000e8");
    }

    /// @notice Very small price: token at $0.00001
    function testVerySmallPrice() public {
        DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
            address(oracle), WETH, 18
        );

        // $0.00001: dolomitePrice = 1e13 (0.00001 * 1e18)
        oracle.setPrice(WETH, 1e13);

        (, int256 answer,,,) = adapter.latestRoundData();
        // 1e13 / 1e10 = 1e3 = 1000 = $0.00001 with 8 decimals
        assertEq(answer, int256(1000), "WETH $0.00001 should be 1000");
    }

    /// @notice Zero price from Dolomite should revert.
    function testRevertsOnZeroPrice() public {
        DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
            address(oracle), WETH, 18
        );

        // Price not set → defaults to 0
        vm.expectRevert(DolomiteOracleAdapter.ZeroDolomitePrice.selector);
        adapter.latestRoundData();
    }
}
