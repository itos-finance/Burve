# Oogabooga Swap Script

This folder contains a simple Node.js script (as an ES module) to execute a swap using the Oogabooga API and a WalletClient.

## Setup

1. Install dependencies:

```
npm install viem node-fetch dotenv
```

2. Create a `.env` file in this directory with the following variables:

```
NEXT_PUBLIC_OOGABOGA_API_URL=https://your-oogabooga-api-url
PRIVATE_KEY=your_private_key
RPC_URL=https://your_rpc_url
CHAIN_ID=your_chain_id
TOKEN_IN=0xTokenInAddress
AMOUNT=1000000000000000000 # Example: 1e18 for 1 token (in wei)
TOKEN_OUT=0xTokenOutAddress
TO=0xYourRecipientAddress
SLIPPAGE=0.01 # Example: 1% slippage
```

## Usage

Run the script with:

```
node swap.mjs
```

The script will execute a swap and print the transaction hash and receipt status.
