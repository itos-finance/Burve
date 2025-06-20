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
	tokenIn: "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c",
	amount: BigInt(1e8),
	tokenOut: "0x657e8C867D8B37dCC18fA4Caead9C45EB088C642",
	to: "0xed63E871F5de87cb1919671eE9e2d331183Eda8f", // the opener contract
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
		transport: http(),
	});

	// Setup PublicClient
	const publicClient = createPublicClient({
		chain: { id: CHAIN_ID, rpcUrls: { default: { http: [RPC_URL] } } },
		transport: http(),
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

	const exec = getAddress("0x2Ef5ffA9884E9ef76883df8212b5d70927B8586");
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

const abi = [
	[
		{
			type: "constructor",
			inputs: [
				{
					name: "_owner",
					type: "address",
					internalType: "address",
				},
			],
			stateMutability: "nonpayable",
		},
		{
			type: "receive",
			stateMutability: "payable",
		},
		{
			type: "function",
			name: "FEE_DENOM",
			inputs: [],
			outputs: [
				{
					name: "",
					type: "uint256",
					internalType: "uint256",
				},
			],
			stateMutability: "view",
		},
		{
			type: "function",
			name: "REFERRAL_WITH_FEE_THRESHOLD",
			inputs: [],
			outputs: [
				{
					name: "",
					type: "uint256",
					internalType: "uint256",
				},
			],
			stateMutability: "view",
		},
		{
			type: "function",
			name: "owner",
			inputs: [],
			outputs: [
				{
					name: "",
					type: "address",
					internalType: "address",
				},
			],
			stateMutability: "view",
		},
		{
			type: "function",
			name: "pause",
			inputs: [],
			outputs: [],
			stateMutability: "nonpayable",
		},
		{
			type: "function",
			name: "paused",
			inputs: [],
			outputs: [
				{
					name: "",
					type: "bool",
					internalType: "bool",
				},
			],
			stateMutability: "view",
		},
		{
			type: "function",
			name: "referralLookup",
			inputs: [
				{
					name: "",
					type: "uint32",
					internalType: "uint32",
				},
			],
			outputs: [
				{
					name: "referralFee",
					type: "uint64",
					internalType: "uint64",
				},
				{
					name: "beneficiary",
					type: "address",
					internalType: "address",
				},
				{
					name: "registered",
					type: "bool",
					internalType: "bool",
				},
			],
			stateMutability: "view",
		},
		{
			type: "function",
			name: "registerReferralCode",
			inputs: [
				{
					name: "_referralCode",
					type: "uint32",
					internalType: "uint32",
				},
				{
					name: "_referralFee",
					type: "uint64",
					internalType: "uint64",
				},
				{
					name: "_beneficiary",
					type: "address",
					internalType: "address",
				},
			],
			outputs: [],
			stateMutability: "nonpayable",
		},
		{
			type: "function",
			name: "renounceOwnership",
			inputs: [],
			outputs: [],
			stateMutability: "nonpayable",
		},
		{
			type: "function",
			name: "swap",
			inputs: [
				{
					name: "tokenInfo",
					type: "tuple",
					internalType: "struct IOBRouter.swapTokenInfo",
					components: [
						{
							name: "inputToken",
							type: "address",
							internalType: "address",
						},
						{
							name: "inputAmount",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "outputToken",
							type: "address",
							internalType: "address",
						},
						{
							name: "outputQuote",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "outputMin",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "outputReceiver",
							type: "address",
							internalType: "address",
						},
					],
				},
				{
					name: "pathDefinition",
					type: "bytes",
					internalType: "bytes",
				},
				{
					name: "executor",
					type: "address",
					internalType: "address",
				},
				{
					name: "referralCode",
					type: "uint32",
					internalType: "uint32",
				},
			],
			outputs: [
				{
					name: "amountOut",
					type: "uint256",
					internalType: "uint256",
				},
			],
			stateMutability: "payable",
		},
		{
			type: "function",
			name: "swapERC20Permit",
			inputs: [
				{
					name: "permit",
					type: "tuple",
					internalType: "struct IOBRouter.erc20PermitInfo",
					components: [
						{
							name: "value",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "deadline",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "v",
							type: "uint8",
							internalType: "uint8",
						},
						{
							name: "r",
							type: "bytes32",
							internalType: "bytes32",
						},
						{
							name: "s",
							type: "bytes32",
							internalType: "bytes32",
						},
					],
				},
				{
					name: "tokenInfo",
					type: "tuple",
					internalType: "struct IOBRouter.swapTokenInfo",
					components: [
						{
							name: "inputToken",
							type: "address",
							internalType: "address",
						},
						{
							name: "inputAmount",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "outputToken",
							type: "address",
							internalType: "address",
						},
						{
							name: "outputQuote",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "outputMin",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "outputReceiver",
							type: "address",
							internalType: "address",
						},
					],
				},
				{
					name: "pathDefinition",
					type: "bytes",
					internalType: "bytes",
				},
				{
					name: "executor",
					type: "address",
					internalType: "address",
				},
				{
					name: "referralCode",
					type: "uint32",
					internalType: "uint32",
				},
			],
			outputs: [
				{
					name: "amountOut",
					type: "uint256",
					internalType: "uint256",
				},
			],
			stateMutability: "nonpayable",
		},
		{
			type: "function",
			name: "swapPermit2",
			inputs: [
				{
					name: "permit2",
					type: "tuple",
					internalType: "struct IOBRouter.permit2Info",
					components: [
						{
							name: "contractAddress",
							type: "address",
							internalType: "address",
						},
						{
							name: "nonce",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "deadline",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "signature",
							type: "bytes",
							internalType: "bytes",
						},
					],
				},
				{
					name: "tokenInfo",
					type: "tuple",
					internalType: "struct IOBRouter.swapTokenInfo",
					components: [
						{
							name: "inputToken",
							type: "address",
							internalType: "address",
						},
						{
							name: "inputAmount",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "outputToken",
							type: "address",
							internalType: "address",
						},
						{
							name: "outputQuote",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "outputMin",
							type: "uint256",
							internalType: "uint256",
						},
						{
							name: "outputReceiver",
							type: "address",
							internalType: "address",
						},
					],
				},
				{
					name: "pathDefinition",
					type: "bytes",
					internalType: "bytes",
				},
				{
					name: "executor",
					type: "address",
					internalType: "address",
				},
				{
					name: "referralCode",
					type: "uint32",
					internalType: "uint32",
				},
			],
			outputs: [
				{
					name: "amountOut",
					type: "uint256",
					internalType: "uint256",
				},
			],
			stateMutability: "nonpayable",
		},
		{
			type: "function",
			name: "transferOwnership",
			inputs: [
				{
					name: "newOwner",
					type: "address",
					internalType: "address",
				},
			],
			outputs: [],
			stateMutability: "nonpayable",
		},
		{
			type: "function",
			name: "transferRouterFunds",
			inputs: [
				{
					name: "tokens",
					type: "address[]",
					internalType: "address[]",
				},
				{
					name: "amounts",
					type: "uint256[]",
					internalType: "uint256[]",
				},
				{
					name: "dest",
					type: "address",
					internalType: "address",
				},
			],
			outputs: [],
			stateMutability: "nonpayable",
		},
		{
			type: "function",
			name: "unpaused",
			inputs: [],
			outputs: [],
			stateMutability: "nonpayable",
		},
		{
			type: "event",
			name: "OwnershipTransferred",
			inputs: [
				{
					name: "previousOwner",
					type: "address",
					indexed: true,
					internalType: "address",
				},
				{
					name: "newOwner",
					type: "address",
					indexed: true,
					internalType: "address",
				},
			],
			anonymous: false,
		},
		{
			type: "event",
			name: "Paused",
			inputs: [
				{
					name: "account",
					type: "address",
					indexed: false,
					internalType: "address",
				},
			],
			anonymous: false,
		},
		{
			type: "event",
			name: "Swap",
			inputs: [
				{
					name: "sender",
					type: "address",
					indexed: false,
					internalType: "address",
				},
				{
					name: "inputAmount",
					type: "uint256",
					indexed: false,
					internalType: "uint256",
				},
				{
					name: "inputToken",
					type: "address",
					indexed: false,
					internalType: "address",
				},
				{
					name: "amountOut",
					type: "uint256",
					indexed: false,
					internalType: "uint256",
				},
				{
					name: "outputToken",
					type: "address",
					indexed: false,
					internalType: "address",
				},
				{
					name: "slippage",
					type: "int256",
					indexed: false,
					internalType: "int256",
				},
				{
					name: "referralCode",
					type: "uint32",
					indexed: false,
					internalType: "uint32",
				},
			],
			anonymous: false,
		},
		{
			type: "event",
			name: "Unpaused",
			inputs: [
				{
					name: "account",
					type: "address",
					indexed: false,
					internalType: "address",
				},
			],
			anonymous: false,
		},
		{
			type: "error",
			name: "AddressEmptyCode",
			inputs: [
				{
					name: "target",
					type: "address",
					internalType: "address",
				},
			],
		},
		{
			type: "error",
			name: "AddressInsufficientBalance",
			inputs: [
				{
					name: "account",
					type: "address",
					internalType: "address",
				},
			],
		},
		{
			type: "error",
			name: "EnforcedPause",
			inputs: [],
		},
		{
			type: "error",
			name: "ExpectedPause",
			inputs: [],
		},
		{
			type: "error",
			name: "FailedInnerCall",
			inputs: [],
		},
		{
			type: "error",
			name: "FeeTooHigh",
			inputs: [
				{
					name: "fee",
					type: "uint64",
					internalType: "uint64",
				},
			],
		},
		{
			type: "error",
			name: "InvalidFeeForCode",
			inputs: [
				{
					name: "fee",
					type: "uint64",
					internalType: "uint64",
				},
			],
		},
		{
			type: "error",
			name: "InvalidNativeTransfer",
			inputs: [],
		},
		{
			type: "error",
			name: "InvalidRouterFundsTransfer",
			inputs: [],
		},
		{
			type: "error",
			name: "MinimumOutputGreaterThanQuote",
			inputs: [
				{
					name: "outputMin",
					type: "uint256",
					internalType: "uint256",
				},
				{
					name: "outputQuote",
					type: "uint256",
					internalType: "uint256",
				},
			],
		},
		{
			type: "error",
			name: "MinimumOutputIsZero",
			inputs: [],
		},
		{
			type: "error",
			name: "NativeDepositValueMismatch",
			inputs: [
				{
					name: "expected",
					type: "uint256",
					internalType: "uint256",
				},
				{
					name: "received",
					type: "uint256",
					internalType: "uint256",
				},
			],
		},
		{
			type: "error",
			name: "NullBeneficiary",
			inputs: [],
		},
		{
			type: "error",
			name: "OwnableInvalidOwner",
			inputs: [
				{
					name: "owner",
					type: "address",
					internalType: "address",
				},
			],
		},
		{
			type: "error",
			name: "OwnableUnauthorizedAccount",
			inputs: [
				{
					name: "account",
					type: "address",
					internalType: "address",
				},
			],
		},
		{
			type: "error",
			name: "ReferralCodeInUse",
			inputs: [
				{
					name: "referralCode",
					type: "uint32",
					internalType: "uint32",
				},
			],
		},
		{
			type: "error",
			name: "SafeERC20FailedOperation",
			inputs: [
				{
					name: "token",
					type: "address",
					internalType: "address",
				},
			],
		},
		{
			type: "error",
			name: "SameTokenInAndOut",
			inputs: [
				{
					name: "token",
					type: "address",
					internalType: "address",
				},
			],
		},
		{
			type: "error",
			name: "SlippageExceeded",
			inputs: [
				{
					name: "amountOut",
					type: "uint256",
					internalType: "uint256",
				},
				{
					name: "outputMin",
					type: "uint256",
					internalType: "uint256",
				},
			],
		},
	],
];

main().catch((err) => {
	console.error(err);
	process.exit(1);
});
