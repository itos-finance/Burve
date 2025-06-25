# Burve Protocol

[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-blue.svg)](https://github.com/Uniswap/v3-core/blob/main/LICENSE)

Burve is a next-gen decentralized exchange protocol that implements multi-pool stableswap functionality.
## Overview

Burve's novel approach to stableswaps includes the following key features:

-   **Expanded Multi-Pools**: Up to 16 tokens in a single pool.
-   **Rehypothecation**: Idle tokens are deposited into other yield sources.
-   **Subset LPing**: Users can choose subsets of the total token set to LP for.
-   **Smarter Concentration**: Dynamically customizable LP concentration.
-   **Built-in Safety Measures**: Circuit breakers prevent accumulating more of a token.

## Architecture

The protocol is built in accordance to EIP-2535's Diamond Contract and functionality is stored in the following facets.

### Core Facets

-   **SwapFacet**: Basic swaps and on-chain simulation of swaps.
-   **ValueFacet**: Deposit with withdraw liquidity with a single token or multiple.
-   **SimplexFacet**: Adjust token and fee settings of the pool.
-   **LockFacet**: Activate manual safeguards on a token.
-   **VaultFacet**: Install and remove rehypothecation vaults.
-   **ValueTokenFacet**: Transfer liquidity between addresses.

## Getting Started

### Prerequisites

-   [Foundry](https://github.com/foundry-rs/foundry)
-   Solidity ^0.8.27

### Installation

1. Clone the repository:

```bash
git clone [https://github.com/itos-finance/Burve](https://github.com/itos-finance/Burve)
cd Burve
```

2. Install dependencies:

```bash
forge install
```

3. Build the project:

```bash
forge build
```

### Testing

Run the test suite:

```bash
forge test
```

### Verification

```bash
forge verify-contract --chain-id 80094 --etherscan-api-key <your_etherscan_api_key> --constructor-args <constructor_args> <contract_address> <contract_source_path>
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Documentation

For detailed documentation about the protocol's architecture and usage, please visit our [documentation site](https://docs.burve.xyz)

## Contact

-   Twitter: [@burve_fi](https://twitter.com/Hyperplex_xyz)
-   Discord: [Burve Community](https://discord.gg/DmF2aVDbcJ)

## Deployment

### Prerequisites

1. Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:

```bash
forge install
```

3. Create a `.env` file with your deployment private key:

```bash
DEPLOYER_PRIVATE_KEY=your_private_key_here
```

## License

The primary license for Burve Protocol is the Business Source License 1.1 (BUSL-1.1), see [LICENSE](LICENSE). However, some files use the MIT License.