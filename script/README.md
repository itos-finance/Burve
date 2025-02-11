# Scripts Usage

This repository contains various scripts located in the `script` folder that facilitate interaction with the smart contracts deployed on the blockchain. Below is a brief overview of the available scripts and their usage.

## Anvil Usage

The scripts are designed to work seamlessly with Anvil, a local Ethereum development environment. To run the scripts, ensure that Anvil is running and your environment is properly configured.

```bash
anvil
```

## Deploying the Contracts

```bash
forge script script/utils/Deploy.s.sol: --rpc-url http://localhost:8545 --broadcast
```

## Environment Variables

The scripts utilize a `.env` file for configuration. Make sure to set the following environment variables in your `.env` file:

-   `DEPLOYER_PUBLIC_KEY`: The public key of the deployer account.
-   `DEPLOYER_PRIVATE_KEY`: The private key of the deployer account.
-   `FORK_URL`: The URL for the Ethereum node to fork from.
-   `CLOSURE_ID`: The ID for the closure context.
-   `AMOUNT`: The amount of tokens to be used in transactions.
-   `RECIPIENT`: The address of the recipient for token transfers.
-   `IN_TOKEN`: The address of the input token for swaps.
-   `OUT_TOKEN`: The address of the output token for swaps.
-   `SQRT_PRICE_LIMIT`: The square root price limit for swaps.

## Running the Scripts

To execute a script, use the following command in your terminal:

```bash
forge script script/utils/AddLiquidity.s.sol: --rpc-url http://localhost:8545 --broadcast
```

```bash
forge script script/utils/RemoveLiquidity.s.sol: --rpc-url http://localhost:8545 --broadcast
```

```bash
forge script script/utils/Swap.s.sol: --rpc-url http://localhost:8545 --broadcast
```

```bash
forge script script/utils/UpdateEdgeFee.s.sol: --rpc-url http://localhost:8545 --broadcast
```

```bash
forge script script/utils/WithdrawFees.s.sol: --rpc-url http://localhost:8545 --broadcast
```
