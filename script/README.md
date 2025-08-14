## Deploying the Contracts

```bash
forge script script/utils/Burve.s.sol: --rpc-url http://localhost:8545 --broadcast
```

## Environment Variables

The scripts utilize a `.env` file for configuration. Make sure to set the following environment variables in your `.env` file:

-   `DEPLOYER_PUBLIC_KEY`: The public key of the deployer account.
-   `DEPLOYER_PRIVATE_KEY`: The private key of the deployer account.
