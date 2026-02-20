# Lender / Looper Architecture

## System Overview

```
+-----------------------------------------------------------------------------------+
|                              USER                                                  |
|  deposit collateral | borrow | repay | withdraw | openLoop | closeLoop | reduceLoop|
+----------+---------+--------+-------+----------+----------+----------+-----------+
           |                                      |
           v                                      v
+---------------------+              +---------------------+
|       LENDER        |<-------------|       LOOPER        |
|  (Ownable, Reentr.) |  authorized  |  (RFTPayer, Reentr.)|
|                     |    looper    |                     |
| - Pool Allowlist    |              | - Stateless         |
| - Position Mgmt    |              | - Iterative Leverage|
| - Lending Pools    |              | - Slippage Guards   |
| - Interest Accrual |              |                     |
| - Liquidation      |              |                     |
+---+-------+---------+              +---------+-----------+
    |       |                                  |
    |       v                                  |
    |  +------------------+                    |
    |  | POSITION PROXY   |                    |
    |  | (CREATE2 per pos)|                    |
    |  | Holds Burve value|                    |
    |  +--------+---------+                    |
    |           |                              |
    v           v                              v
+---------------------------------------------------------------+
|                    BURVE DIAMOND                               |
|  (SimplexDiamond / ValueTokenFacet / IBurveMultiValue)         |
|  - addValue / removeValue / addSingleForValue                  |
|  - value positions keyed by (address, closureId)               |
|  - RFT callback mechanism for token requests                   |
+---------------------------------------------------------------+
```

## Contract Relationships

```
+------------+     +-------------------+     +------------------+
|  Chainlink |     |   InterestRate    |     |  PositionValuer  |
|  Oracles   |---->|   Model (lib)     |     |  (library)       |
+------------+     | - 2-slope rates   |     | - Oracle pricing |
                   | - FullMath safe   |     | - Pro-rata share |
                   +-------------------+     | - Collateral     |
                          |                  |   factors        |
                          v                  +--------+---------+
                   +------+------+                    |
                   |   LENDER    |<-------------------+
                   | (main hub)  |
                   +------+------+
                          |
              +-----------+-----------+
              |                       |
     +--------+--------+    +--------+--------+
     | PositionProxy   |    | LenderStorage   |
     | (per position)  |    | (structs only)  |
     | - execute()     |    | - LoanPosition  |
     | - transferToken |    | - LendingPool   |
     +--------+--------+    +-----------------+
              |
              v
     +--------+--------+
     | Burve Diamond   |
     | ValueTokenFacet |
     +-----------------+
```

## Data Flow: Opening a Leveraged Loop

```
User                    Looper                   Lender              Burve Diamond
  |                       |                        |                      |
  |-- openLoop(pool, cid, token, amount, iters, minVal) -->|              |
  |                       |                        |                      |
  |  safeTransferFrom --->|                        |                      |
  |  (inToken, amount)    |                        |                      |
  |                       |                        |                      |
  |                       |-- addSingleForValue ---|--------------------->|
  |                       |   (deposit tokens)     |                      |
  |                       |<-- valueReceived ------|----------------------|
  |                       |                        |                      |
  |                       |-- depositCollateralFor(user, pool, cid, value) |
  |                       |                        |-- deploy proxy ----->|
  |                       |                        |   (CREATE2)          |
  |                       |                        |-- transferFrom ----->|
  |                       |                        |   value -> proxy     |
  |                       |<-- positionId ---------|                      |
  |                       |                        |                      |
  |                       |  === LOOP (1..N) ===   |                      |
  |                       |                        |                      |
  |                       |-- borrow(posId, token, 70% of value) ------->|
  |                       |<-- tokens sent --------|                      |
  |                       |                        |                      |
  |                       |-- addSingleForValue ---|--------------------->|
  |                       |<-- newValue ---------- |----------------------|
  |                       |                        |                      |
  |                       |-- addCollateral(posId, newValue) ----------->|
  |                       |                        |-- value -> proxy     |
  |                       |                        |                      |
  |                       |  === END LOOP ===      |                      |
  |                       |                        |                      |
  |                       |  check: totalValue >= minVal                  |
  |<-- positionId --------|                        |                      |
```

## Data Flow: Closing a Loop

```
User                    Looper                   Lender              Burve Diamond
  |                       |                        |                      |
  |-- closeLoop(posId, outToken, minOut) --------->|                      |
  |                       |                        |                      |
  |                       |  for each pool token:  |                      |
  |  safeTransferFrom --->|  (repayment tokens)    |                      |
  |                       |-- repay(posId, tok, $) |                      |
  |                       |                        |-- safeTransferFrom ->|
  |                       |                        |   (Looper -> Lender) |
  |                       |                        |                      |
  |                       |-- withdrawCollateral(posId, allValue) ------->|
  |                       |                        |-- proxy.execute ---->|
  |                       |                        |   value -> Looper    |
  |                       |                        |                      |
  |                       |-- removeValue(cid, value) ------------------>|
  |                       |<-- tokens returned ----|----------------------|
  |                       |                        |                      |
  |<-- outToken + others --|  (safeTransfer all)   |                      |
```

## Data Flow: Liquidation

```
Liquidator              Lender                  PositionProxy       Burve Diamond
  |                       |                        |                      |
  |-- liquidate(posId, debtToken, repayAmount) --->|                      |
  |                       |                        |                      |
  |                       |  1. Check: position is unhealthy              |
  |                       |     adjColUSD * LIQUIDATION_LTV < debtUSD     |
  |                       |                        |                      |
  |  safeTransferFrom --->|  2. Pull repayment     |                      |
  |  (debtToken)          |     tokens from        |                      |
  |                       |     liquidator         |                      |
  |                       |                        |                      |
  |                       |  3. Update debt:       |                      |
  |                       |     tokenBorrows -= repayAmount               |
  |                       |     totalBorrowed -= repayAmount              |
  |                       |                        |                      |
  |                       |  4. Calculate seize:   |                      |
  |                       |     repaidUSD = oracle(repayAmount)           |
  |                       |     seizeUSD = repaidUSD * 1.05              |
  |                       |     seizeValue = proportional value           |
  |                       |                        |                      |
  |                       |  5. Transfer seized value                     |
  |                       |     pos.depositedValue -= seizeValue          |
  |                       |--  proxy.execute ----->|                      |
  |                       |                        |-- ValueTokenFacet -->|
  |                       |                        |   .transfer(liq,     |
  |<-- value position ----|------------------------|   seizeValue)        |
  |    received           |                        |                      |
```

## Position Isolation (CREATE2 Proxy Pattern)

```
Problem: Burve's AssetBook merges balances by address.
         If Lender held all positions directly, they'd merge.

Solution: Each position gets a unique CREATE2 proxy.

                    +-------------------+
                    |      LENDER       |
                    |  deploys proxies  |
                    +--------+----------+
                             |
               CREATE2 with salt = keccak256(positionId)
                             |
              +--------------+--------------+
              |              |              |
     +--------+---+  +------+-----+  +-----+------+
     | Proxy #0   |  | Proxy #1   |  | Proxy #2   |
     | salt: h(0) |  | salt: h(1) |  | salt: h(2) |
     +------+-----+  +------+-----+  +------+-----+
            |               |               |
            v               v               v
     +-----------+   +-----------+   +-----------+
     | Burve     |   | Burve     |   | Burve     |
     | AssetBook |   | AssetBook |   | AssetBook |
     | (Proxy 0) |   | (Proxy 1) |   | (Proxy 2) |
     +-----------+   +-----------+   +-----------+
     Each proxy has its own AssetBook entry in Burve.
     Positions never merge. Isolated accounting.
```

## Interest Rate Model (Two-Slope)

```
  Borrow Rate (APR)
       |
  81%  |                                                    /
       |                                                   /
       |                                                  /  Slope 2
       |                                                 /   (+75%)
       |                                                /
  6%   |-----------------------------------------------*
       |                                  Slope 1     /
       |                           (+4%)             /
       |                                            /
  2%   *------------------------------------------/
       |        Base Rate (2%)
       +----------+----------+----------+----------+---> Utilization
       0%        20%        40%       60%  Optimal  100%
                                           (80%)
```

## Health Factor & Liquidation Thresholds

```
  LTV Ratio
       |
 100%  |  ===================================================
       |                     INSOLVENT (bad debt)
  85%  |  ---------------------------------------------------  <- LIQUIDATION_LTV
       |           LIQUIDATABLE ZONE
       |           (liquidators can seize collateral + 5% bonus)
  80%  |  ---------------------------------------------------  <- MAX_LTV
       |           DANGER ZONE (no new borrows allowed)
       |
       |           HEALTHY ZONE
       |           (borrow, withdraw freely)
   0%  |  ===================================================

  Health Factor = (adjustedCollateralUSD * LIQUIDATION_LTV) / debtUSD

  HF > 1.0  => Healthy (cannot be liquidated)
  HF <= 1.0 => Unhealthy (can be liquidated)
  HF = max  => No debt (infinite health)
```

## Lending Pool Mechanics

```
  LPs deposit tokens:                 Borrowers borrow tokens:

  LP ---> depositLiquidity(token, $)  Borrower ---> borrow(posId, token, $)
          |                                         |
          v                                         v
  +------------------+                    +-----------------+
  | LendingPool      |                    | Health Check    |
  | totalDeposited+= |                    | debtUSD <=      |
  | shares minted    |                    | adjColUSD*80%   |
  +------------------+                    +-----------------+
          |                                         |
          v                                         v
  lpShares[token][LP]+= shares           tokenBorrows[posId][token]+= amount
                                         totalBorrowed+= amount

  Interest accrues continuously:
  +-------------------------------------------------------------------+
  | _accrueInterest(token):                                           |
  |   timeDelta = now - lastAccrual                                   |
  |   multiplier = 1 + rate * timeDelta / YEAR                        |
  |   borrowIndex *= multiplier                                       |
  |   interestEarned = totalBorrowed * (multiplier - 1)               |
  |   reserveCut = interestEarned * 10%                               |
  |   totalBorrowed += interestEarned                                 |
  |   totalDeposited += interestEarned - reserveCut                   |
  +-------------------------------------------------------------------+
```

## Oracle-Based Position Valuation

```
  valuePositionUSD(pool, closureId, posValue, posBgtValue):

  1. Query Burve:  getClosureValue(closureId)
     => (n, _, balances[16], valueStaked, bgtValueStaked)

  2. Compute total:
     totalStaked = valueStaked + bgtValueStaked
     totalPosition = posValue + posBgtValue

  3. For each token i (0..n-1):
     userShare = balances[i] * totalPosition / totalStaked

     +-- Chainlink --+
     | latestRound() |---> price, feedDecimals
     +---------------+

     tokenUSD = userShare * price / 10^feedDecimals

  4. Sum all tokenUSD => total position USD value

  weightedValuePositionUSD adds per-token collateral factors:
     adjustedUSD += tokenUSD * collateralFactor / 1e18
```

## File Structure

```
src/integrations/
├── lender/
│   ├── Lender.sol              # Main lending contract (Ownable, ReentrancyGuard)
│   │                           #   - depositCollateral / depositCollateralFor
│   │                           #   - borrow / repay
│   │                           #   - withdrawCollateral
│   │                           #   - depositLiquidity / withdrawLiquidity
│   │                           #   - liquidate
│   │                           #   - collectPositionEarnings
│   ├── LenderStorage.sol       # Structs: LoanPosition, LendingPool
│   ├── InterestRateModel.sol   # Two-slope utilization model (library)
│   ├── PositionValuer.sol      # Oracle-based position pricing (library)
│   ├── PositionProxy.sol       # CREATE2 proxy for position isolation
│   └── AggregatorV3Interface.sol  # Chainlink interface
├── looper/
│   └── Looper.sol              # Stateless leverage orchestrator
│                               #   - openLoop (iterative deposit-borrow)
│                               #   - closeLoop (repay-withdraw-remove)
│                               #   - reduceLoop (partial deleverage)
│                               #   - estimateLoop (pure estimate)
└── condenser/
    └── Condenser.sol           # Batch swap helper for collectEarnings
```

## Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| MAX_LTV | 80% | Maximum loan-to-value for borrowing |
| LIQUIDATION_LTV | 85% | LTV threshold for liquidation eligibility |
| LIQUIDATION_BONUS | 5% | Bonus collateral awarded to liquidators |
| MIN_POSITION_USD | $100 | Minimum position size (dust prevention) |
| BASE_RATE | 2% APR | Minimum borrow rate |
| SLOPE1 | 4% | Rate increase 0-80% utilization |
| SLOPE2 | 75% | Rate increase 80-100% utilization |
| OPTIMAL_UTILIZATION | 80% | Kink point in interest rate curve |
| RESERVE_FACTOR | 10% | Protocol revenue share of interest |
| MAX_STALENESS | 1 hour | Oracle price freshness requirement |
