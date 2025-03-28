// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console as console} from "forge-std/console.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {MockERC4626} from "../../test/mocks/MockERC4626.sol";
import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {LiqFacet} from "../../src/multi/facets/LiqFacet.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {ViewFacet} from "../../src/multi/facets/ViewFacet.sol";
import {EdgeFacet} from "../../src/multi/facets/EdgeFacet.sol";
import {BurveMultiLPToken} from "../../src/multi/LPToken.sol";
import {TokenRegLib} from "../../src/multi/Token.sol";
import {ClosureId} from "../../src/multi/Closure.sol";

struct TokenData {
    string symbol;
    address token;
    address vault;
}

struct SetData {
    address diamond;
    TokenData[] tokens;
}

contract AddLiq is Script {
    string constant DEPLOYMENTS = "deployments.json";

    string[] public setNames;
    mapping(string setName => SetData setData) public sets;

    function setUp() public {
        string memory json = vm.readFile(DEPLOYMENTS);

        setNames = vm.parseJsonKeys(json, ".");
        for (uint i = 0; i < setNames.length; ++i) {
            string memory name = setNames[i];
            bytes memory encodedSetData = vm.parseJson(json, string.concat(".", name));
            sets[name] = abi.decode(encodedSetData, (SetData));
        }
    }

    function run() external {
        vm.startBroadcast(msg.sender);

        for (uint i = 0; i < setNames.length; ++i) {
            string memory name = setNames[i];
            SetData memory setData = sets[name];

            console.log("\nAdding liq for set: ", name);

            // Diamond and facets
            SimplexDiamond diamond = SimplexDiamond(payable(setData.diamond));
            LiqFacet liqFacet = LiqFacet(setData.diamond);
            SimplexFacet simplexFacet = SimplexFacet(setData.diamond);
            SwapFacet swapFacet = SwapFacet(setData.diamond);
            ViewFacet viewFacet = ViewFacet(setData.diamond);
            EdgeFacet edgeFacet = EdgeFacet(setData.diamond);

            // Amounts for each token
            uint128[] memory amounts = new uint128[](setData.tokens.length);
            address[] memory tokensInClosure = new address[](setData.tokens.length);
            for (uint8 j = 0; j < amounts.length; ++j) {
                address tokenAddress = setData.tokens[j].token;

                uint8 index = viewFacet.getTokenIndex(tokenAddress);
                tokensInClosure[index] = tokenAddress;

                MockERC20 token = MockERC20(tokenAddress);
                amounts[index] = uint128(100_000_000 * 10 ** uint256(token.decimals()));

                // mint tokens to sender
                token.mint(msg.sender, uint256(amounts[index]));

                // approve transfer to the diamond
                token.approve(setData.diamond, uint256(amounts[index]));
            }

            // Get closure
            uint16 closureId = ClosureId.unwrap(viewFacet.getClosureId(tokensInClosure));
            console.log("Closure Id: ", closureId);

            // Add liquidity
            uint256 shares = liqFacet.addLiq(msg.sender, closureId, amounts);
            console.log("Liquidity added successfully!");
            console.log("Shares received:", shares);
        }

        vm.stopBroadcast();
    }
}