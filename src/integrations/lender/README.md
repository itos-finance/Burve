# BurveLender — Lending Against Burve Positions

Borrow tokens against your Burve LP positions. Deposit your value position as collateral, borrow stablecoins, and keep earning Burve trading fees while leveraged.

## Architecture

```
                           BURVE DIAMOND
                     ┌─────────────────────┐
                     │  Closures (AMM)      │
                     │  ┌─────┐  ┌─────┐   │
User's LP  ────────> │  │USDC │  │USDT │   │  Value position represents
Position             │  └─────┘  └─────┘   │  pro-rata share of all tokens
                     │  valueStaked: 12k    │  in the closure
                     └─────────────────────┘
                               │
                    ValueTokenFacet.transferFrom()
                               │
                               ▼
                     ┌─────────────────────┐
                     │   BURVE LENDER      │
                     │                     │
                     │  ┌───────────────┐  │
                     │  │ Position #0   │  │     ┌──────────────┐
                     │  │ proxy: 0xABC  │──┼────>│PositionProxy │ Holds value in
                     │  │ value: 200    │  │     │ (CREATE2)    │ Burve's AssetBook
                     │  │ debt: $150    │  │     └──────────────┘
                     │  └───────────────┘  │
                     │                     │
                     │  Lending Pools       │     ┌──────────────┐
                     │  ┌──────┐ ┌──────┐  │     │  LPs deposit │
                     │  │ USDC │ │ USDT │◄─┼─────│  tokens to   │
                     │  │ pool │ │ pool │  │     │  earn yield   │
                     │  └──────┘ └──────┘  │     └──────────────┘
                     └─────────────────────┘
                               │
                     Oracle Valuation (collateral)
                               │
                               ▼
                     ┌─────────────────────┐
                     │   PRICE ORACLES     │
                     │ AggregatorV3Interface│
                     │                     │
                     │ USDC → $1.00 (1e8)  │
                     │ USDT → $1.00 (1e8)  │
                     │ HONEY → $1.00 (1e8) │
                     └─────────────────────┘
```

## Value Flow — How Borrowing Works

```
1. USER DEPOSITS LP INTO BURVE
   ┌──────┐     addValue()      ┌────────────┐
   │ User │ ──────────────────> │   Burve    │
   │      │ <────────────────── │  Diamond   │
   │      │   value position    │            │
   └──────┘   (200 units)      └────────────┘

2. USER DEPOSITS COLLATERAL INTO LENDER
   ┌──────┐  depositCollateral() ┌────────────┐  transferFrom()  ┌───────┐
   │ User │ ───────────────────> │  Burve     │ ───────────────> │ Proxy │
   │      │  value: 200 units    │  Lender    │  value → proxy   │ 0xABC │
   └──────┘                      └────────────┘                  └───────┘
   Lender checks: collateralValueUSD >= $100 (MIN_POSITION_USD)

3. USER BORROWS TOKENS
   ┌──────┐     borrow()        ┌────────────┐
   │ User │ ──────────────────> │  Burve     │  Checks:
   │      │ <────────────────── │  Lender    │  debtUSD <= colUSD × 80%
   │      │   150 USDC tokens   │            │  Sends from lending pool
   └──────┘                     └────────────┘

4. COLLATERAL VALUATION (continuous)
   ┌───────┐  getClosureValue() ┌────────────┐  latestRoundData() ┌────────┐
   │ Proxy │ ──────────────────>│   Burve    │──────────────────>│ Oracle │
   │ 0xABC │  nominal balances  │  Diamond   │  token prices      │ (CL)   │
   └───────┘                    └────────────┘                    └────────┘
                                      │
                                      ▼
              userShare = closureBalance × positionValue / totalValueStaked
              usdValue  = Σ (userShare[i] × price[i] / 1e8)
```

## Liquidation Flow

```
                    Health Factor < 1.0
                           │
                           ▼
  ┌────────────┐    liquidate()     ┌────────────┐
  │ Liquidator │ ─────────────────> │   Burve    │
  └────────────┘                    │   Lender   │
                                    └─────┬──────┘
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    ▼                     ▼                     ▼
           1. removeValue()      2. Swap via Router     3. Distribute
           via proxy
  ┌───────┐    ┌────────────┐    ┌────────────┐    ┌────────────────────┐
  │ Proxy │───>│   Burve    │    │ OogaBooga  │    │ Repay debt to pool │
  │       │<───│  Diamond   │    │  Router    │    │ 3% bonus → caller  │
  │       │    └────────────┘    └────────────┘    │ 2% → protocol      │
  │       │    Returns USDC,USDT  non-debt tokens  │ remainder → borrower│
  └───────┘    to proxy           swapped to debt   └────────────────────┘
```

## Oracle System

BurveLender uses the **Chainlink AggregatorV3Interface** for price feeds:

```solidity
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt,
        uint256 updatedAt, uint80 answeredInRound
    );
}
```

**How prices are used:**
- **Collateral valuation**: Reads nominal balances from Burve closure, multiplies each token's share by its oracle price
- **Debt valuation**: Converts raw borrow amounts to USD using oracle price and token decimals
- **Staleness check**: Reverts if oracle data is older than 1 hour

**Berachain context**: Berachain mainnet does NOT have traditional Chainlink push-based price feeds. It has Chainlink Data Streams (pull-based), Pyth, API3, and a native Slinky oracle. For production, adapter contracts wrapping these behind `AggregatorV3Interface` are needed. For testing, we deploy mock aggregators with `setPriceFeed()`.

```
Collateral USD = Σ (nominalShare[i] × oraclePrice[i] / 1e8)
                     │                      │
                     │                      └── Chainlink 8-decimal price
                     └── 18-decimal normalized (from Burve closure)

Debt USD = rawAmount × oraclePrice × 1e18 / (1e8 × 10^decimals)
```

## Interest Rate Model

Two-slope utilization-based model:

```
Borrow Rate
    81% ┤                                    ╱
        │                                  ╱
        │                                ╱
        │                              ╱
     6% ┤─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─╱
        │                      ╱╱╱
     2% ┤─ ─ ─ ─ ─ ─ ─ ─╱╱╱╱╱
        │          ╱╱╱╱╱╱
        ├────╱╱╱╱╱╱──────┬──────────┤
        0%              80%         100%  Utilization

Base rate:   2% APR
Slope 1:     +4% at 80% utilization (optimal)
Slope 2:     +75% from 80% to 100%
Reserve:     10% of interest goes to protocol
```

## Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| MAX_LTV | 80% | Maximum loan-to-value ratio for borrowing |
| LIQUIDATION_LTV | 85% | Health factor = colUSD × 85% / debtUSD |
| LIQUIDATION_PENALTY | 5% | Total penalty on liquidation |
| CALLER_BONUS | 3% | Portion of penalty paid to liquidator |
| PROTOCOL_CUT | 2% | Portion of penalty retained by protocol |
| MIN_POSITION_USD | $100 | Minimum collateral value to open a position |
| MAX_STALENESS | 1 hour | Oracle price max age before revert |

## Why CREATE2 Proxies?

Burve's `AssetBook` merges all value deposited by the same address into the same closure. If BurveLender held all positions directly, every user's collateral would be merged into one position — making individual liquidation impossible.

Each position gets its own `PositionProxy` deployed via CREATE2, giving it a unique address in Burve's AssetBook:

```
Position 0 → Proxy 0xAAA → AssetBook[0xAAA][closure3] = 200 value
Position 1 → Proxy 0xBBB → AssetBook[0xBBB][closure3] = 500 value
Position 2 → Proxy 0xCCC → AssetBook[0xCCC][closure7] = 150 value
```

## Contract Structure

```
src/integrations/lender/
├── BurveLender.sol          Main contract: deposit, borrow, repay, liquidate
├── BurveLenderStorage.sol   Position and lending pool structs
├── PositionProxy.sol        CREATE2 proxy (1 per position)
├── PositionValuer.sol       Oracle-based USD valuation library
├── InterestRateModel.sol    Two-slope interest rate math
└── AggregatorV3Interface.sol  Chainlink oracle interface

src/integrations/looper/
└── BurveLooper.sol          Leveraged position opener (iterative borrow-deposit)
```

## Testing

```bash
# Unit tests (no fork required)
make test-lender          # 15 tests
make test-looper          # 6 tests

# Fork tests against live Berachain diamond
make anvil-fork           # Start Anvil in terminal 1
make test-fork            # Run in terminal 2

# E2E liquidation scenario (simulation)
make liq-e2e              # Deploy → seed → borrow → crash → liquidate → verify
```

### Fork Test Results

```
testForkDepositAndBorrow     — Deposits into live diamond, borrows at 10% LTV
  collateral USD: $200    health factor: 8.5

testForkLiquidation          — Borrows at 75% LTV, crashes oracle, liquidates
  collateral USD: $200    borrow: $150
  HF before crash: 1.13   HF after crash: 0.51
  → liquidation successful, position cleared

testForkLiquidationRevertsWhenHealthy — Confirms healthy positions can't be liquidated
```
