// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./BaseScript.sol";
import {Test} from "forge-std/Test.sol";
import {ClosureId} from "../../src/multi/closure/Id.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {IDiamond} from "Commons/Diamond/interfaces/IDiamond.sol";
import {IDiamondCut} from "Commons/Diamond/interfaces/IDiamondCut.sol";

contract CutTesting is BaseScript, Test {
    function run() external {
        address sender = 0xae54b397aC7Bacd6E45875af9728835bD4A31e5f;
        deal(sender, 10 ether);

        address recipient = sender;
        uint16 closureId = 10;

        address inToken = address(tokens[3]); // NECT
        console2.log("before deal");
        deal(inToken, sender, 1e8);

        console2.log("dealt");

        address outToken = address(tokens[1]); // USDT

        uint128 maxValue = 0; // 0 means no maximum value requirement

        SwapFacet newSwap = new SwapFacet();
        bytes4[] memory swapSelectors = new bytes4[](2);
        swapSelectors[0] = SwapFacet.swap.selector;
        swapSelectors[1] = SwapFacet.simSwap.selector;

        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);

        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(newSwap),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: swapSelectors
        });

        // owner.
        vm.prank(0x9293f9FFC43F6fce06290285919541E963D87F51);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        console2.log("Cut facet at address:", address(newSwap));

        vm.prank(sender);
        swapFacet.swap(recipient, inToken, outToken, 1e18, maxValue, closureId);
    }
}
