import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
  encodeFunctionData,
  zeroAddress,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import dotenv from "dotenv";
import { ADDRESSES, OOGABOOGA_API, POLL_INTERVAL_MS, MAX_TOKENS, CHAIN_ID } from "./config.mjs";
import { BURVE_LENDER_ABI, DIAMOND_ABI, ERC20_ABI } from "./abi.mjs";

dotenv.config();

const RPC_URL = process.env.RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const OOGABOOGA_API_KEY = process.env.OOGABOOGA_API_KEY;

const berachain = {
  id: CHAIN_ID,
  name: "Berachain",
  nativeCurrency: { name: "BERA", symbol: "BERA", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
};

const publicClient = createPublicClient({
  chain: berachain,
  transport: http(RPC_URL),
});

let walletClient;
let account;

if (PRIVATE_KEY) {
  account = privateKeyToAccount(PRIVATE_KEY);
  walletClient = createWalletClient({
    account,
    chain: berachain,
    transport: http(RPC_URL),
  });
}

// Cache pool tokens to avoid repeated calls
let poolTokensCache = null;

async function getPoolTokens() {
  if (poolTokensCache) return poolTokensCache;
  poolTokensCache = await publicClient.readContract({
    address: ADDRESSES.DIAMOND,
    abi: DIAMOND_ABI,
    functionName: "getTokens",
  });
  console.log(`Pool tokens (${poolTokensCache.length}):`, poolTokensCache);
  return poolTokensCache;
}

async function getNextPositionId() {
  return publicClient.readContract({
    address: ADDRESSES.BURVE_LENDER,
    abi: BURVE_LENDER_ABI,
    functionName: "nextPositionId",
  });
}

async function getPosition(positionId) {
  const [borrower, pool, closureId, proxy, depositedValue, depositedBgtValue] =
    await publicClient.readContract({
      address: ADDRESSES.BURVE_LENDER,
      abi: BURVE_LENDER_ABI,
      functionName: "positions",
      args: [positionId],
    });
  return { borrower, pool, closureId, proxy, depositedValue, depositedBgtValue };
}

async function getHealthFactor(positionId) {
  return publicClient.readContract({
    address: ADDRESSES.BURVE_LENDER,
    abi: BURVE_LENDER_ABI,
    functionName: "healthFactor",
    args: [positionId],
  });
}

async function getCurrentBorrow(positionId, token) {
  return publicClient.readContract({
    address: ADDRESSES.BURVE_LENDER,
    abi: BURVE_LENDER_ABI,
    functionName: "currentBorrow",
    args: [positionId, token],
  });
}

async function getCollateralValueUSD(positionId) {
  return publicClient.readContract({
    address: ADDRESSES.BURVE_LENDER,
    abi: BURVE_LENDER_ABI,
    functionName: "collateralValueUSD",
    args: [positionId],
  });
}

async function getBorrowValueUSD(positionId) {
  return publicClient.readContract({
    address: ADDRESSES.BURVE_LENDER,
    abi: BURVE_LENDER_ABI,
    functionName: "borrowValueUSD",
    args: [positionId],
  });
}

/// Fetch swap route from OogaBooga API.
async function getSwapRoute(tokenIn, amount, tokenOut, receiver) {
  const url = new URL(`${OOGABOOGA_API}/v1/swap`);
  url.searchParams.set("tokenIn", tokenIn);
  url.searchParams.set("amount", amount.toString());
  url.searchParams.set("tokenOut", tokenOut);
  url.searchParams.set("to", receiver);
  url.searchParams.set("slippage", "0.01");

  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${OOGABOOGA_API_KEY}` },
  });

  if (!res.ok) {
    console.error(`OogaBooga API error: ${res.status} ${res.statusText}`);
    return null;
  }

  return res.json();
}

/// Build liquidation txData and debtTokens arrays.
async function buildLiquidationParams(positionId) {
  const poolTokens = await getPoolTokens();

  // Find debt tokens and their amounts
  const debtTokens = [];
  const debtAmounts = {};

  for (const token of poolTokens) {
    const owed = await getCurrentBorrow(positionId, token);
    if (owed > 0n) {
      debtTokens.push(token);
      debtAmounts[token] = owed;
    }
  }

  if (debtTokens.length === 0) {
    console.log(`  Position ${positionId}: no debt tokens found`);
    return null;
  }

  // Primary debt token (first one with debt) — swap non-debt tokens into this
  const primaryDebtToken = debtTokens[0];

  // Build txData: for each non-debt pool token, get swap route to primary debt token
  const txData = new Array(MAX_TOKENS).fill("0x");

  for (let i = 0; i < poolTokens.length; i++) {
    const token = poolTokens[i];

    // Skip if this is a debt token (no swap needed)
    if (debtTokens.includes(token)) continue;

    // Get the BurveLender's balance of this token after removeValue
    // We can't know this in advance, so we estimate based on position value
    // The actual amount will be determined during the liquidation call.
    // For the OogaBooga route, we use a placeholder amount and rely on the
    // router to handle the actual balance.
    // NOTE: In production, you'd want to simulate the removeValue first.

    try {
      const route = await getSwapRoute(
        token,
        1n, // placeholder — the router calldata should work for any amount
        primaryDebtToken,
        ADDRESSES.BURVE_LENDER
      );

      if (route && route.tx && route.tx.data) {
        txData[i] = route.tx.data;
      }
    } catch (err) {
      console.error(`  Failed to get swap route for token ${i}:`, err.message);
    }
  }

  return { txData, debtTokens };
}

/// Attempt to liquidate a single position.
async function liquidatePosition(positionId) {
  console.log(`\nAttempting liquidation of position ${positionId}...`);

  const params = await buildLiquidationParams(positionId);
  if (!params) return;

  const { txData, debtTokens } = params;

  // Simulate first
  try {
    await publicClient.simulateContract({
      address: ADDRESSES.BURVE_LENDER,
      abi: BURVE_LENDER_ABI,
      functionName: "liquidate",
      args: [BigInt(positionId), txData, debtTokens],
      account: account.address,
    });
    console.log(`  Simulation passed for position ${positionId}`);
  } catch (err) {
    console.error(`  Simulation failed for position ${positionId}:`, err.message);
    return;
  }

  // Execute
  try {
    const hash = await walletClient.writeContract({
      address: ADDRESSES.BURVE_LENDER,
      abi: BURVE_LENDER_ABI,
      functionName: "liquidate",
      args: [BigInt(positionId), txData, debtTokens],
    });

    console.log(`  Liquidation tx sent: ${hash}`);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    console.log(`  Liquidation confirmed: status=${receipt.status}`);
  } catch (err) {
    console.error(`  Liquidation tx failed for position ${positionId}:`, err.message);
  }
}

/// Main poll loop: scan all positions, check health, liquidate if needed.
async function pollPositions() {
  const nextId = await getNextPositionId();
  console.log(`\n[${new Date().toISOString()}] Scanning ${nextId} positions...`);

  for (let i = 0n; i < nextId; i++) {
    try {
      const pos = await getPosition(i);

      // Skip empty/closed positions
      if (pos.borrower === zeroAddress || pos.depositedValue === 0n) continue;

      const hf = await getHealthFactor(i);
      const colUSD = await getCollateralValueUSD(i);
      const debtUSD = await getBorrowValueUSD(i);

      const hfFormatted = formatEther(hf);
      const colFormatted = formatEther(colUSD);
      const debtFormatted = formatEther(debtUSD);

      if (hf < 10n ** 18n) {
        console.log(
          `  [LIQUIDATABLE] Position ${i}: HF=${hfFormatted}, col=$${colFormatted}, debt=$${debtFormatted}`
        );
        await liquidatePosition(Number(i));
      } else {
        console.log(
          `  Position ${i}: HF=${hfFormatted}, col=$${colFormatted}, debt=$${debtFormatted}`
        );
      }
    } catch (err) {
      console.error(`  Error checking position ${i}:`, err.message);
    }
  }
}

/// Entry point.
async function main() {
  console.log("=== BurveLender Liquidation Bot ===");
  console.log(`Lender:  ${ADDRESSES.BURVE_LENDER}`);
  console.log(`Diamond: ${ADDRESSES.DIAMOND}`);
  console.log(`Router:  ${ADDRESSES.ROUTER}`);
  console.log(`Poll interval: ${POLL_INTERVAL_MS}ms`);
  console.log(`Wallet: ${account ? account.address : "READ-ONLY (no PRIVATE_KEY)"}`);
  console.log("");

  // Initial poll
  await pollPositions();

  // Continuous polling
  setInterval(async () => {
    try {
      await pollPositions();
    } catch (err) {
      console.error("Poll error:", err.message);
    }
  }, POLL_INTERVAL_MS);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
