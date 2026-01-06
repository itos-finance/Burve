# BERA Airdrop Contract

This contract distributes 100,000 BERA to 44 recipients based on their points allocation.

## Contract Details

- **Total Distribution**: 100,000 BERA
- **Total Recipients**: 44 addresses
- **Total Points**: 84,176.82
- **Contract**: `src/BeraAirdrop.sol`

## Distribution Calculation

Each recipient receives BERA proportional to their points:
```
Amount = (Recipient Points / Total Points) × 100,000 BERA
```

The amounts are calculated in wei and the last recipient gets the remainder to ensure the total is exactly 100,000 BERA.

## Deployment

### Option 1: Using the Deployment Script (Recommended)

```bash
# Set your deployer private key in .env
export DEPLOYER_PRIVATE_KEY=your_private_key_here

# Deploy the contract
forge script script/DeployBeraAirdrop.s.sol --rpc-url <BERACHAIN_RPC_URL> --broadcast

# The deployment script will:
# 1. Deploy the BeraAirdrop contract
# 2. Display contract address and details
```

**Note**: The deployment script does NOT automatically fund the contract. You need to send 100,000 BERA separately.

### Option 2: Manual Deployment

```bash
# Deploy
forge create src/BeraAirdrop.sol:BeraAirdrop \
  --rpc-url <BERACHAIN_RPC_URL> \
  --private-key <DEPLOYER_PRIVATE_KEY>

# Fund the contract with 100,000 BERA
cast send <CONTRACT_ADDRESS> \
  --value 100000ether \
  --rpc-url <BERACHAIN_RPC_URL> \
  --private-key <DEPLOYER_PRIVATE_KEY>
```

## Usage

### Distribute to All Recipients (Single Transaction)

This is the simplest method but uses the most gas:

```bash
cast send <CONTRACT_ADDRESS> \
  "distributeAll()" \
  --rpc-url <BERACHAIN_RPC_URL> \
  --private-key <OWNER_PRIVATE_KEY> \
  --gas-limit 10000000
```

### Distribute in Batches (Gas-Limited Scenarios)

If the gas limit is too low for a single transaction, distribute in batches:

```bash
# Distribute to recipients 0-10
cast send <CONTRACT_ADDRESS> \
  "distributeBatch(uint256,uint256)" 0 10 \
  --rpc-url <BERACHAIN_RPC_URL> \
  --private-key <OWNER_PRIVATE_KEY>

# Distribute to recipients 10-20
cast send <CONTRACT_ADDRESS> \
  "distributeBatch(uint256,uint256)" 10 20 \
  --rpc-url <BERACHAIN_RPC_URL> \
  --private-key <OWNER_PRIVATE_KEY>

# Continue until all recipients are covered...
```

### Distribute to a Single Recipient

```bash
# Distribute to recipient at index 0
cast send <CONTRACT_ADDRESS> \
  "distributeSingle(uint256)" 0 \
  --rpc-url <BERACHAIN_RPC_URL> \
  --private-key <OWNER_PRIVATE_KEY>
```

## Querying Contract State

### Check Contract Balance
```bash
cast balance <CONTRACT_ADDRESS> --rpc-url <BERACHAIN_RPC_URL>
```

### Check if Distribution is Complete
```bash
cast call <CONTRACT_ADDRESS> "distributed()" --rpc-url <BERACHAIN_RPC_URL>
```

### Get Recipient Count
```bash
cast call <CONTRACT_ADDRESS> "recipientCount()" --rpc-url <BERACHAIN_RPC_URL>
```

### Get Specific Recipient Info
```bash
# Get recipient at index 0
cast call <CONTRACT_ADDRESS> "recipients(uint256)" 0 --rpc-url <BERACHAIN_RPC_URL>
```

### Check Owner
```bash
cast call <CONTRACT_ADDRESS> "owner()" --rpc-url <BERACHAIN_RPC_URL>
```

## Safety Features

1. **Owner Only**: Only the contract owner (deployer) can trigger distributions
2. **One-Time Distribution**: The `distributeAll()` function can only be called once
3. **Balance Check**: Contract verifies it has sufficient balance before distributing
4. **Emergency Withdrawal**: Owner can withdraw funds if needed (before distribution)

## Emergency Withdrawal

If you need to withdraw funds (before distribution):

```bash
cast send <CONTRACT_ADDRESS> \
  "withdraw()" \
  --rpc-url <BERACHAIN_RPC_URL> \
  --private-key <OWNER_PRIVATE_KEY>
```

## Testing

Run the test suite to verify the contract:

```bash
forge test --match-path test/BeraAirdrop.t.sol -vv
```

All tests should pass:
- ✅ Constructor initialization
- ✅ Distribution to all recipients
- ✅ Batch distribution
- ✅ Single recipient distribution
- ✅ Cannot distribute twice
- ✅ Only owner can distribute
- ✅ Insufficient balance check
- ✅ Withdrawal function
- ✅ Total distribution equals 100k BERA
- ✅ Individual recipient amounts are correct

## Top 10 Recipients

| Rank | Address | BERA Amount |
|------|---------|-------------|
| 1 | 0x6eA0cd91291BaF975Ec0E5Ec5b5803455360150b | 29,871.47 |
| 2 | 0xc137942872586E5847d66025c9aE04b89053Cb58 | 25,078.23 |
| 3 | 0x5e031c60a35Cd0762970d8e63e6aeE2d4C9CBC6B | 11,207.88 |
| 4 | 0x6e7465acBaa3217Bdcc4C17CDbE1DaDbb4356377 | 6,513.65 |
| 5 | 0x81785e00055159FCae25703D06422aBF5603f8A8 | 5,588.08 |
| 6 | 0x36f4E1803f6fF34562dB567f347dea00DeC87246 | 4,572.92 |
| 7 | 0xa916b0F22D9B198268C637506CF83b360716dc32 | 3,527.44 |
| 8 | 0x4C6b778e5a5395C86e6F09E1E7b72C9Db3958175 | 2,478.54 |
| 9 | 0x9F1854Fa6D7647BBba30ED79AC767c1424a98f30 | 2,253.01 |
| 10 | 0x17e5eC84dB5d8210e875B929981d480F122eBA14 | 1,833.47 |

## Gas Estimates

- **distributeAll()**: ~1,820,000 gas
- **distributeBatch(0, 10)**: ~430,000 gas
- **distributeSingle(0)**: ~58,000 gas

**Note**: Actual gas costs may vary based on network conditions.
