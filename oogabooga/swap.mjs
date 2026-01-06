import { createWalletClient, createPublicClient, http, getAddress } from "viem";
import fetch from "node-fetch";
import dotenv from "dotenv";
dotenv.config();

// Replace with your actual private key and chain info
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const RPC_URL = process.env.RPC_URL;
const CHAIN_ID = Number(process.env.CHAIN_ID || 31337);

// const OOGABOOGA_API_URL = "https://bartio.api.oogabooga.io";
const OOGABOOGA_API_URL = "https://mainnet.api.oogabooga.io";

const swapParams = {
	tokenIn: "0x779Ded0c9e1022225f8E0630b35a9b54bE713736",
	amount: BigInt(1e8),
	tokenOut: "0x549943e04f40284185054145c6E4e9568C1D3241",
	to: "0xaBa9D5ce40a81Da22526092FE4bA0517DeF2FBD3", // the opener contract
	slippage: Number(process.env.SLIPPAGE || 0.01),
};

const headers = {
	Authorization: `Bearer ${process.env.OOGABOGA_API_KEY}`,
};

async function main() {
	// Setup WalletClient
	const client = createWalletClient({
		account: PRIVATE_KEY,
		chain: { id: CHAIN_ID, rpcUrls: { default: { http: [RPC_URL] } } },
		transport: http(
			"https://aged-empty-voice.bera-mainnet.quiknode.pro/a27fa88ce19f90319ad1b9a4f4d6f96a78903d01/"
		),
	});

	// Setup PublicClient
	const publicClient = createPublicClient({
		chain: { id: CHAIN_ID, rpcUrls: { default: { http: [RPC_URL] } } },
		transport: http(
			"https://aged-empty-voice.bera-mainnet.quiknode.pro/a27fa88ce19f90319ad1b9a4f4d6f96a78903d01/"
		),
	});

	await swap(client, publicClient, swapParams);
}

const swap = async (client, publicClient, swapParams) => {
	const publicApiUrl = new URL(`${OOGABOOGA_API_URL}/v1/swap`);
	publicApiUrl.searchParams.set("tokenIn", swapParams.tokenIn);
	publicApiUrl.searchParams.set("amount", swapParams.amount.toString());
	publicApiUrl.searchParams.set("tokenOut", swapParams.tokenOut);
	publicApiUrl.searchParams.set("to", swapParams.to);
	publicApiUrl.searchParams.set("slippage", swapParams.slippage.toString());
	console.log("swapParams", { swapParams });

	const res = await fetch(publicApiUrl, { headers });
	const { tx, routerParams, routerAddr } = await res.json();
	console.log("tx", tx);
	console.log("routerParams", JSON.stringify(routerParams));
	console.log("routerAddr", routerAddr);

	const exec = getAddress(routerParams.executor);
	console.log("exec", exec);

	// console.log("Submitting swap...");
	// const hash = await client.sendTransaction({
	// 	from: tx.from,
	// 	to: tx.to,
	// 	data: tx.data,
	// 	value: tx.value ? BigInt(tx.value) : 0n,
	// });
	// console.log("hash", hash);

	// const rcpt = await publicClient.waitForTransactionReceipt({ hash });
	// console.log("Swap complete", rcpt.status);
};

main().catch((err) => {
	console.error(err);
	process.exit(1);
});
