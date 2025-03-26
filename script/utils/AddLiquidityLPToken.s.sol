// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";
import {BurveMultiLPToken} from "../../src/multi/LPToken.sol";
import {ClosureId} from "../../src/multi/Closure.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract AddLiquidityLPToken is BaseScript {
    constructor() BaseScript() {
        deploymentType = "btc"; // This is a BTC pool
    }

    function run() external {
        // Start broadcasting
        vm.startBroadcast(_getPrivateKey());

        // BTC Pool LP Token (closure 3)
        // BurveMultiLPToken lpToken = new BurveMultiLPToken(
        //     ClosureId.wrap(3),
        //     0xd01B3fE5219D390c7B73E1bBbaA5ED8980a6FC9a
        // );
        BurveMultiLPToken lpToken = BurveMultiLPToken(
            0xA68c74B6F195C60fAbf81249EB3b16b0c1Da7067
        );

        ClosureId cid = lpToken.cid();
        console2.log("closureId", ClosureId.unwrap(cid));

        // Token addresses and amounts
        address depositToken = 0xdA92aE7D59e7Fb497BCf531Fb64B3d375Bb6Fd45; // First token
        uint128 amount = 7_000_000_000_000_000_000; // Amount to deposit
        address recipient = 0x0D31fFC3Df44921586a0d6d358045c4f6866Aba7; // Recipient address

        // Mint and approve tokens
        _mintAndApproveLpToken(
            depositToken,
            _getSender(),
            address(lpToken),
            amount
        );
        console2.log("complete");
        console2.log("\nAdding liquidity to BTC pool using LPToken:");
        console2.log("LP Token:", address(lpToken));
        console2.log("Deposit Token:", depositToken);
        console2.log("Amount:", amount);
        console2.log("Recipient:", recipient);

        // Add liquidity using single token mint
        lpToken.mint(recipient, depositToken, amount);

        // console2.log("\nLiquidity added successfully!");
        // console2.log("Shares received:", shares);

        vm.stopBroadcast();
    }

    function runMultiTokenMint() external {
        // Start broadcasting
        vm.startBroadcast(_getPrivateKey());

        // BTC Pool LP Token (closure 3)
        BurveMultiLPToken lpToken = BurveMultiLPToken(
            0x32f3f4487327C5CA791D40A0347C3b92d5edaabB
        );

        // Get number of tokens in registry
        // uint8 numTokens = simplexFacet.numVertices();

        // Create amounts array (all zeros by default)
        uint128[] memory amounts = new uint128[](3);

        // Set amounts for BTC tokens (WBTC and uniBTC)
        // uint8 wbtcIndex = viewFacet.getTokenIndex(
        //     0x688a5D3B7EcAd835469408ddcDFE4Fee6e2d881D
        // ); // WBTC
        // uint8 unibtcIndex = viewFacet.getTokenIndex(
        //     0xdA92aE7D59e7Fb497BCf531Fb64B3d375Bb6Fd45
        // ); // uniBTC

        // Set equal amounts for both tokens (7 tokens with 18 decimals)
        amounts[0] = 7000000000000000000;
        amounts[1] = 7000000000000000000;

        // Mint and approve tokens
        _mintAndApprove(
            0x688a5D3B7EcAd835469408ddcDFE4Fee6e2d881D,
            _getSender(),
            7000000000000000000
        );
        _mintAndApprove(
            0xdA92aE7D59e7Fb497BCf531Fb64B3d375Bb6Fd45,
            _getSender(),
            7000000000000000000
        );

        console2.log("here");

        console2.log("\nAdding liquidity to BTC pool using multi-token mint:");
        console2.log("LP Token:", address(lpToken));
        console2.log("WBTC amount:", amounts[0]);
        console2.log("uniBTC amount:", amounts[1]);
        console2.log("Recipient:", 0x0D31fFC3Df44921586a0d6d358045c4f6866Aba7);

        // Add liquidity using multi-token mint
        uint256 shares = lpToken.mint(
            0x0D31fFC3Df44921586a0d6d358045c4f6866Aba7,
            amounts
        );

        console2.log("\nLiquidity added successfully!");
        console2.log("Shares received:", shares);

        vm.stopBroadcast();
    }
}
