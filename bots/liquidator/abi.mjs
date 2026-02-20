export const BURVE_LENDER_ABI = [
  // Read functions
  {
    type: "function",
    name: "nextPositionId",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "positions",
    inputs: [{ name: "positionId", type: "uint256" }],
    outputs: [
      { name: "borrower", type: "address" },
      { name: "pool", type: "address" },
      { name: "closureId", type: "uint16" },
      { name: "proxy", type: "address" },
      { name: "depositedValue", type: "uint256" },
      { name: "depositedBgtValue", type: "uint256" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "healthFactor",
    inputs: [{ name: "positionId", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "currentBorrow",
    inputs: [
      { name: "positionId", type: "uint256" },
      { name: "token", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "collateralValueUSD",
    inputs: [{ name: "positionId", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "borrowValueUSD",
    inputs: [{ name: "positionId", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "router",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  // Write function
  {
    type: "function",
    name: "liquidate",
    inputs: [
      { name: "positionId", type: "uint256" },
      {
        name: "txData",
        type: "bytes[16]",
      },
      { name: "debtTokens", type: "address[]" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
];

export const DIAMOND_ABI = [
  {
    type: "function",
    name: "getTokens",
    inputs: [],
    outputs: [{ name: "", type: "address[]" }],
    stateMutability: "view",
  },
];

export const ERC20_ABI = [
  {
    type: "function",
    name: "approve",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "balanceOf",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
];
