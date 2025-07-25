This is a simple process for adding tokens and their closures to the OmniPool.

1. Deploy a NoopVault (as needed)
2. Deploy the Add_MEAD_RUSD_PYUSD script. Deployment.s.sol (rename and update tokens as needed)
3. Fund the Add_MEAD_RUSD_PYUSD contract with the tokens needed to initialize the closures
4. Run the Execution script. Execution.s.sol to add the closures to the OmniPool and transfer ownership back to the multisig

## Fork testing

Before running the scripts, you need to fork the chain you are executing on. An example of this is the FAdd_MEAD_RUSD_PYUSD.sol script.

```
forge test --fork-url $FORK_URL -vvvv
```

## Deployment

```
forge script script/ops/Deployment.s.sol:Deployment --rpc-url $RPC_URL -vvvv
```
