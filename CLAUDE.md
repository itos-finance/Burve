# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Burve is a next-generation decentralized exchange protocol implementing multi-pool stableswap functionality with advanced features:

- **Multi-Pool Support**: Up to 16 tokens in a single pool
- **Rehypothecation**: Idle tokens deposited into yield sources
- **Subset LPing**: Users can LP for subsets of the total token set
- **Dynamic Concentration**: Customizable LP concentration
- **Circuit Breakers**: Built-in safety measures

## Architecture

### Diamond Pattern (EIP-2535)

Burve uses the Diamond proxy pattern with functionality split across facets:

- **SwapFacet**: Basic swaps and on-chain swap simulation
- **ValueFacet**: Deposit/withdraw liquidity (single or multiple tokens)
- **SimplexFacet**: Adjust token and fee settings
- **LockFacet**: Activate manual safeguards on tokens
- **VaultFacet**: Install/remove rehypothecation vaults
- **ValueTokenFacet**: Transfer liquidity between addresses

### Core Concepts

**Storage (`src/multi/Store.sol`)**: Diamond storage pattern using `MULTI_STORAGE_POSITION`. Contains:
- `AssetBook assets`: Tracks asset holdings
- `TokenRegistry tokenReg`: Token metadata
- `VaultStorage _vaults`: Rehypothecation vault storage
- `Simplex simplex`: Pool configuration (name, fees, efficiency factors)
- `mapping(ClosureId => Closure) closures`: Token subset pools
- `mapping(VertexId => Vertex) vertices`: Individual token tracking

**Closures (`src/multi/closure/Closure.sol`)**: Represent subsets of tokens within the pool. A closure operates on a specific set of tokens identified by `ClosureId`. Each closure maintains:
- Target values for balances
- Current balances in nominal terms
- Value staked and earnings distribution

**Vertices (`src/multi/vertex/Vertex.sol`)**: Each vertex tracks a single token's balance in real terms. Vertices supply tokens to closures and manage rehypothecation through vaults.

**Balance Types (`src/README.md`)**: Four token balance types to consider:
- **Value**: Balance swapped 1:1 with value token
- **Reserve**: Amount in a closure that can't be swapped directly, supports slippage
- **Fees**: Tokens distributed as fee earnings to assets
- **Amount**: Literal amount swapped (sum of value, reserve, and fees)

**Simplex (`src/multi/Simplex.sol`)**: Stores pool-wide configuration:
- Efficiency factors (`esX128`) for each token
- Edge fees between token pairs
- Protocol earnings and revenue share
- Search parameters for value calculations

## Common Commands

### Build and Test

```bash
# Build the project
forge build

# Run all tests
forge test

# Run tests with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/facets/SwapFacet.t.sol

# Run specific test function
forge test --match-test testExactInputSwap

# Run tests with gas reporting
forge test --gas-report

# Run tests matching a pattern
forge test --match-contract SwapFacetTest
```

### Deployment

```bash
# Deploy from environment variables (requires .env setup)
forge script script/DeployFromEnv.s.sol --rpc-url <RPC_URL> --broadcast

# Deploy to Berachain
forge script script/DeployBerachainUSD.s.sol --rpc-url <RPC_URL> --broadcast

# Verify contract on Berachain
forge verify-contract --chain-id 80094 --etherscan-api-key <KEY> --constructor-args <ARGS> <ADDRESS> <CONTRACT_PATH>
```

### Utility Scripts

Scripts in `script/utils/` provide common operations:
- `AddValue.s.sol`: Add liquidity to pool
- `RemoveValue.s.sol`: Remove liquidity from pool
- `Swap.s.sol`: Execute swaps
- `FacetCutScript.sol`: Base for facet upgrades

### Development Workflow

1. **Facet Upgrades**: Use Diamond Cut pattern
   - Deploy new facet: `script/cut/DeployFacet.s.sol`
   - Create cut proposal: `script/cut/FacetCut.sol`
   - Execute cut: `script/cut/ExecuteFacetCut.s.sol`

2. **Testing**: Tests follow pattern in `test/facets/`
   - Inherit from `MultiSetupTest` (in `test/facets/MultiSetup.u.sol`)
   - Use `_newDiamond()`, `_newTokens()`, `_initializeClosure()`
   - Fund test accounts with `_fundAccount()`

## Key Files and Locations

### Source Structure
- `src/multi/`: Main protocol implementation (Diamond, facets, core logic)
- `src/multi/facets/`: Diamond facet implementations
- `src/multi/closure/`: Closure (token subset) logic
- `src/multi/vertex/`: Vertex (individual token) logic
- `src/integrations/`: External integrations (BGT, adjustors, vaults)
- `src/single/`: Legacy single-pool implementation

### Testing
- `test/facets/`: Facet-specific tests
- `test/mocks/`: Mock contracts (MockERC20, MockERC4626)
- `test/utils/`: Testing utilities

### Scripts
- `script/utils/`: Utility scripts for common operations
- `script/migrate_*/`: Migration scripts for protocol upgrades
- `script/berachain/`: Berachain-specific deployments

### Configuration
- `foundry.toml`: Solidity 0.8.30, via-ir enabled, 100 optimizer runs
- `remappings.txt`: Import path mappings
- `.env`: Required for deployment (DEPLOYER_PRIVATE_KEY)

## Important Patterns

### Adjustors
Adjustors handle decimal conversions and value transformations. Located in `src/integrations/adjustor/`:
- `NullAdjustor`: No adjustment
- `DecimalAdjustor`: Handle different decimal precision
- `FixedAdjustor`: Fixed rate conversion
- `MixedAdjustor`: Combination of adjustors
- `E4626ViewAdjustor`: ERC4626 vault view adjustor

### Vault Integration
Vaults enable rehypothecation. Types defined in `VaultType` enum:
- Standard ERC4626 vaults
- Custom vault implementations
- Managed in `src/multi/vertex/VaultProxy.sol`

### Fixed-Point Math
Uses 128-bit fixed-point (`X128` suffix = value << 128):
- `esX128`: Efficiency factors
- `edgeFeesX128`: Fee rates
- `targetX128`: Target values
Utilities in `src/FullMath.sol` for overflow-safe operations

## External Tools

### Oogabooga Swap Script
Located in `oogabooga/`: Node.js script for executing swaps via Oogabooga API
```bash
cd oogabooga
npm install
node swap.mjs
```

Requires `.env` configuration with RPC_URL, PRIVATE_KEY, token addresses, etc.

## Branch Strategy

- Main development branch: `Dev.20250528`
- Feature branches follow pattern: `feature/POL20`
- Use main development branch for PRs, not `main`
