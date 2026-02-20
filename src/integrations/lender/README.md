# Lender — Lending Against Burve Positions

Borrow tokens against your Burve LP positions. Deposit your value position as collateral, borrow stablecoins, and keep earning Burve trading fees while leveraged.

## Full System Model — Token Flow Across All Layers

```
 LAYER 1: USERS                LAYER 2: BURVE LENDER            LAYER 3: BURVE DIAMOND           LAYER 4: DOLOMITE VAULT
 ════════════════               ══════════════════════            ══════════════════════            ═══════════════════════

 ┌─────────────┐               ┌──────────────────────┐         ┌──────────────────────┐         ┌────────────────────┐
 │  Borrower   │               │   Lender.sol    │         │   Burve Diamond      │         │  Dolomite ERC4626  │
 │             │               │                      │         │                      │         │                    │
 │ 1. addValue ├──────────────────────────────────────>│  Closure 3             │         │  USDC Vault         │
 │    on Burve │               │                      │  ┌──────────────────┐  │         │  ┌──────────────┐  │
 │             │               │                      │  │ valueStaked: 10k │  │         │  │ totalShares  │  │
 │ 2. deposit- │  value token  │  Position #0         │  │ balances:        │  │ deposit │  │ held by Burve│  │
 │    Collat-  ├──────────────>│  ┌────────────────┐  │  │  USDC: 5000e18   │──┼────────>│  │              │  │
 │    eral()   │               │  │ proxy: 0xAAA   │──┼─>│  USDT: 5000e18   │  │         │  │ Other users' │  │
 │             │               │  │ value: 200     │  │  └──────────────────┘  │         │  │ deposits too │  │
 │ 3. borrow() │  USDC tokens  │  │ debt: $150     │  │                        │         │  └──────────────┘  │
 │<────────────┼───────────────│  └────────────────┘  │  AssetBook:            │         │                    │
 │  (from pool)│               │                      │  ┌──────────────────┐  │ withdraw│                    │
 │             │               │  Position #1         │  │ [0xAAA][cid3]=200│  │<────────│  maxWithdraw()     │
 │             │               │  ┌────────────────┐  │  │ [0xBBB][cid3]=500│  │         │  constrains how    │
 │             │               │  │ proxy: 0xBBB   │──┼─>│ [0xCCC][cid7]=150│  │         │  much Burve can    │
 │             │               │  │ value: 500     │  │  └──────────────────┘  │         │  pull out           │
 │             │               │  │ debt: $300     │  │                        │         │                    │
 │             │               │  └────────────────┘  │  Each proxy is a       │         │  highWaterMark     │
 │             │               │                      │  SEPARATE address      │         │  auto-locks vertex │
 │             │               │  ┌──────────────────┐│  in the AssetBook      │         │  if vault loses $  │
 │ LP (lender) │  USDC deposit │  │ Lending Pools    ││                        │         └────────────────────┘
 │─────────────┼──────────────>│  │ ┌──────────────┐ ││                        │
 │             │               │  │ │USDC pool     │ ││                        │
 │             │               │  │ │deposited: 10k│ ││                        │
 │             │               │  │ │borrowed:  5k │ ││                        │
 │             │               │  │ │available: 5k │ ││                        │
 │             │               │  │ └──────────────┘ ││                        │
 │             │               │  └──────────────────┘│                        │
 └─────────────┘               └──────────────────────┘         └──────────────────────┘
```

**Two completely separate token pools exist:**

1. **Collateral side** (right): User's value position lives in Burve Diamond, tokens in Dolomite vault. Lender never touches these tokens directly — only the proxy can call removeValue.
2. **Lending pool side** (left): LP deposits sit in Lender contract. **These tokens NEVER go to Dolomite.** They are held as raw ERC20 balances in Lender.

## Fund Isolation Proof

### Claim: Liquidating Position A does NOT affect Position B's collateral

**Evidence — Position isolation via CREATE2 proxies:**

```
Position A: proxy 0xAAA → AssetBook[0xAAA][cid3] = 200 value
Position B: proxy 0xBBB → AssetBook[0xBBB][cid3] = 500 value

Liquidate Position A:
  1. proxy 0xAAA calls removeValue(200)
  2. Closure.removeValue computes: scale = 200 / totalValueStaked
     For each token: withdraw = scale × closure.balance[token]
  3. Closure.valueStaked decreases by 200
  4. AssetBook[0xAAA][cid3] = 0

Position B after liquidation:
  AssetBook[0xBBB][cid3] = 500  (UNCHANGED)
  B's share of remaining closure = 500 / (totalValueStaked - 200)
  B's proportional token share: SAME OR SLIGHTLY LARGER
```

**Why B is unaffected:**
- `removeValue` withdraws a **proportional** fraction of each token (ValueFacet.sol → Closure.sol:218-247)
- Before removal, `trimAllBalances()` distributes any pending trading fee earnings to ALL holders (including B)
- B's AssetBook entry is never read or modified during A's liquidation
- B's share of the remaining closure tokens is preserved (or slightly increased due to rounding in B's favor)

### Claim: LP deposits in lending pools are never exposed to Dolomite

**Evidence — token flow trace:**

```
depositLiquidity(USDC, 1000e18):
  → IERC20(USDC).safeTransferFrom(LP, address(Lender), 1000e18)
  → lendingPools[USDC].totalDeposited += 1000e18
  → Tokens sit in Lender's ERC20 balance. Period.

borrow(positionId, USDC, 500e18):
  → IERC20(USDC).safeTransfer(borrower, 500e18)
  → Tokens go from Lender → borrower. NOT to Dolomite.

repay / liquidation:
  → Tokens return to Lender via safeTransferFrom or removeValue
```

LP tokens never enter a Burve closure, never enter a Dolomite vault. They are held as raw ERC20 balances.

### Claim: Other Burve LP users (not using Lender) are unaffected

**Evidence — removeValue is identical to a normal LP withdrawal:**

When Lender's proxy calls `removeValue(200)`, the Burve Diamond executes the exact same code path as any LP removing their position. There is no special treatment:

```
1. trimAllBalances()       — distributes pending fees to ALL holders
2. Proportional removal    — withdraw[i] = (value/totalValue) × balance[i]
3. Vertex.withdraw()       — pulls tokens from vault
4. AssetBook.remove()      — decreases proxy's recorded value
5. Closure.finalize()      — decreases valueStaked
```

Other LPs in the same closure see:
- Their `valueStaked` share: **unchanged** (their value units didn't change)
- Their proportional token share: **unchanged or slightly increased** (fewer total value units, same tokens)
- Their pending earnings: **collected** (trimAllBalances runs first)

### Claim: PositionProxy prevents unauthorized fund movement

**Evidence — PositionProxy.sol access control:**

```solidity
constructor() { lender = msg.sender; }  // Set at deploy, immutable

function execute(address target, bytes calldata data) external returns (bytes memory) {
    if (msg.sender != lender) revert OnlyLender();  // ONLY Lender
    ...
}

function transferToken(address token, address to, uint256 amount) external {
    if (msg.sender != lender) revert OnlyLender();  // ONLY Lender
    ...
}
```

Not even the position owner can move tokens from the proxy. Only Lender can.

## Risk Model — Where Funds CAN Be Lost

### Risk 1: Bad Debt (LP loss)

```
Scenario:
  Position collateral = $100 USD
  Position debt = $85 USD (85% LTV, just liquidatable)
  Oracle price drops 20% during liquidation tx

Liquidation:
  removeValue returns ~$80 of tokens (was $100 before price drop)
  After swap: $78 of debt token available
  Debt owed: $85

  RESULT: $7 shortfall. Debt is cleared from pool.totalBorrowed
  but only $78 was recovered. LP pool is short $7.

  WHO LOSES: Lending pool LPs absorb the $7 loss.
  Borrower and other borrowers are unaffected.
```

**Mitigation**: Conservative MAX_LTV + liquidation penalty provides buffer. At 80% MAX_LTV and 5% penalty, price must drop ~10% instantaneously to create bad debt.

### Risk 2: Dolomite Vault Withdrawal Failure (liquidation blocked)

```
Scenario:
  Dolomite USDC vault has 95% utilization (95% lent out)
  vault.maxWithdraw(burve) returns only 5% of Burve's deposit
  Lender tries to liquidate a position

Code path:
  liquidate() → proxy.execute(removeValue) → Vertex.withdraw()
    → VaultProxy.withdraw() checks:
      maxWithdrawable = vault.maxWithdraw() = SMALL
      if (amount > maxWithdrawable) → revert WithdrawLimited

  RESULT: Liquidation reverts. Position stays unhealthy but
  cannot be liquidated until Dolomite utilization drops.

  WHO LOSES: No one immediately. But if oracle prices keep falling
  while liquidation is blocked, bad debt accumulates.
```

**Mitigation needed**: Dynamic LTV based on vault withdrawability, or liquid reserves.

### Risk 3: Dolomite Vault Value Loss (collateral devaluation)

```
Scenario:
  Dolomite borrower defaults → bad debt socialized to vault depositors
  Vault share value drops 3%

Code path:
  E4626.isValid() checks: (DUST + totalAssets) >= highWaterMark
    → returns FALSE
  Vertex.validateLock() → locks the vertex

  RESULT: Vertex auto-locks. No new deposits or swaps.
  Withdrawals (removeValue) still work but return fewer tokens.
  All Burve positions in that closure lose ~3% value.
  Lender positions lose collateral value → may trigger liquidation.

  WHO LOSES: ALL users with tokens in that closure (Burve LPs
  AND Lender borrowers equally).
```

## Per-Token Collateral Factors

Different tokens carry different risk. The `collateralFactor` discounts riskier tokens:

```
Example: Position with $500 USDC + $500 HONEY in closure

  USDC factor = 95%  →  $500 × 0.95 = $475 borrowing power
  HONEY factor = 80% →  $500 × 0.80 = $400 borrowing power
                         ────────────────────────────────────
  Raw collateral:                    $1,000
  Adjusted collateral:              $  875
  Max borrow (80% of adjusted):    $  700

  Effective LTV by token:
    USDC:  95% × 80% = 76% effective LTV
    HONEY: 80% × 80% = 64% effective LTV
```

Set via `setCollateralFactor(token, factor)` (onlyOwner). View via:
- `getTokenMargin(token)` → factor, effectiveMaxLTV, effectiveLiqLTV, price
- `getPositionBreakdown(positionId)` → per-token raw/adjusted values, borrowing capacity
- `maxBorrowable(positionId, token)` → max additional tokens borrowable (capped by pool liquidity)

## Dolomite Exposure Analysis

Lender does NOT borrow from Dolomite. Burve DEPOSITS into Dolomite ERC4626 vaults as a yield source. The risk is asymmetric:

```
                     NOT this:                          THIS:
            ┌────────────────────────┐      ┌────────────────────────┐
            │ Dolomite liquidates    │      │ Dolomite vault loses   │
            │ Lender's position │      │ value from bad debt    │
            │ (doesn't happen —      │      │ → Burve's vault shares │
            │  Burve is a depositor, │      │   worth less           │
            │  not a borrower)       │      │ → All Burve closure    │
            └────────────────────────┘      │   balances decrease    │
                                            │ → Lender collateral│
                                            │   drops in USD value    │
                                            │ → Positions may become  │
                                            │   liquidatable          │
                                            └────────────────────────┘
```

**Dolomite uses OracleAggregatorV2** (Chronicle + Redstone + Kodiak TWAP on Berachain), not Chainlink AggregatorV3. Lender should use the same oracle source via adapter contracts to avoid price divergence.

## Liquidation Flow — Detailed

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

Lender uses the **Chainlink AggregatorV3Interface** for price feeds:

```solidity
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt,
        uint256 updatedAt, uint80 answeredInRound
    );
}
```

**How prices are used:**
- **Collateral valuation**: Reads nominal balances from Burve closure, multiplies each token's share by its oracle price, applies per-token collateral factor
- **Debt valuation**: Converts raw borrow amounts to USD using oracle price and token decimals
- **Staleness check**: Reverts if oracle data is older than 1 hour

**Berachain context**: Berachain mainnet does NOT have traditional Chainlink push-based price feeds. Dolomite uses Chronicle + Redstone + Kodiak TWAP via OracleAggregatorV2. The `DolomiteOracleAdapter` wraps Dolomite's oracle behind `AggregatorV3Interface` for production use. For testing, we deploy mock aggregators with `setPriceFeed()`.

### DolomiteOracleAdapter

Converts Dolomite prices (precision: `36 - tokenDecimals` decimals) to Chainlink format (8 decimals):

```
Dolomite:  getPrice(token) → MonetaryPrice { value: priceWithPrecision }
Adapter:   latestRoundData() → (0, chainlinkAnswer, now, now, 0)

Conversion: chainlinkAnswer = dolomitePrice / 10^(28 - tokenDecimals)

Examples:
  USDC (6 dec):  1e30 (Dolomite $1.00) → 1e8 (Chainlink)
  WETH (18 dec): 2000e18 (Dolomite $2000) → 2000e8 (Chainlink)
  WBTC (8 dec):  60000e28 (Dolomite $60k) → 60000e8 (Chainlink)
```

**Deployed Dolomite oracle addresses (Berachain mainnet):**
- OracleAggregatorV2: `0xa150Ef2D5827dB283321D15d62d5D07fB41d636E`
- DolomiteMargin: `0x003Ca23Fd5F0ca87D01F6eC6CD14A8AE60c2b97D`

Deploy one adapter per token:
```solidity
DolomiteOracleAdapter adapter = new DolomiteOracleAdapter(
    0xa150Ef2D5827dB283321D15d62d5D07fB41d636E, // Dolomite OracleAggregatorV2
    tokenAddress,
    tokenDecimals
);
lender.setPriceFeed(tokenAddress, address(adapter), tokenDecimals);
```

```
Collateral USD = Σ (nominalShare[i] × oraclePrice[i] × collateralFactor[i] / 1e8)
                     │                      │                    │
                     │                      │                    └── Per-token risk weight
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
| MAX_LTV | 80% | Maximum loan-to-value ratio (applied to risk-adjusted collateral) |
| LIQUIDATION_LTV | 85% | Health factor threshold (adjusted collateral × 85% / debt) |
| LIQUIDATION_PENALTY | 5% | Total penalty on liquidation |
| CALLER_BONUS | 3% | Portion of penalty paid to liquidator |
| PROTOCOL_CUT | 2% | Portion of penalty retained by protocol |
| MIN_POSITION_USD | $100 | Minimum collateral value to open a position |
| MAX_STALENESS | 1 hour | Oracle price max age before revert |
| Collateral factors | Per-token | 1e18 = 100%, lower = riskier token = less borrowing power |

## Why CREATE2 Proxies?

Burve's `AssetBook` merges all value deposited by the same address into the same closure. If Lender held all positions directly, every user's collateral would be merged into one position — making individual liquidation impossible.

Each position gets its own `PositionProxy` deployed via CREATE2, giving it a unique address in Burve's AssetBook:

```
Position 0 → Proxy 0xAAA → AssetBook[0xAAA][closure3] = 200 value
Position 1 → Proxy 0xBBB → AssetBook[0xBBB][closure3] = 500 value
Position 2 → Proxy 0xCCC → AssetBook[0xCCC][closure7] = 150 value

Liquidating Position 0 calls removeValue on 0xAAA only.
0xBBB and 0xCCC are never touched. Their value is unchanged.
```

## Open Risks Requiring Resolution

| Risk | Severity | Status | Mitigation Path |
|------|----------|--------|-----------------|
| Bad debt (collateral < debt at liquidation) | High | Unmitigated | LP insurance pool or bad debt socialization |
| Dolomite withdrawal blocked (high util) | High | Unmitigated | Dynamic LTV or liquid reserve buffer |
| Dolomite vault value loss | Medium | Partial (highWaterMark) | Tighter LTV, vault health monitoring |
| Oracle divergence from Dolomite | Medium | Mitigated | DolomiteOracleAdapter wraps Dolomite oracle behind AggregatorV3 |
| Multi-token debt surplus distribution | Medium | Fixed | Surplus calc uses PRECISION denominator (3% caller, 2% protocol, 95% borrower) |

## Contract Structure

```
src/integrations/lender/
├── Lender.sol              Main contract: deposit, borrow, repay, liquidate
├── LenderStorage.sol       Position and lending pool structs
├── PositionProxy.sol            CREATE2 proxy (1 per position)
├── PositionValuer.sol           Oracle-based USD valuation library
├── InterestRateModel.sol        Two-slope interest rate math
├── AggregatorV3Interface.sol    Chainlink oracle interface
└── DolomiteOracleAdapter.sol    Wraps Dolomite oracle behind AggregatorV3Interface

src/integrations/looper/
└── Looper.sol              Leveraged position opener (iterative borrow-deposit)
```

## Testing

```bash
# Unit tests (no fork required)
make test-lender          # 38 lender + 10 adapter = 48 tests
make test-looper          # 11 tests

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
