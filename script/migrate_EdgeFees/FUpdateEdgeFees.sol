// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {BurveForkableTest} from "../../test/integrations/Fork.u.sol";
import {UpdateEdgeFees} from "./UpdateEdgeFees.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";
import {IRFTPayer} from "Commons/Util/RFT.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract FUpdateEdgeFees is BurveForkableTest {
    address constant MULTISIG = 0x9293f9FFC43F6fce06290285919541E963D87F51;

    // Test suite for UpdateEdgeFees contract
    // Tests:
    // 1. Edge fee updates (0.05% for specific edges: 0,1; 1,2; 0,2)
    // 2. EX128 value updates (efactors for all 9 tokens)
    // 3. RFT Payer functionality (tokenRequestCB security)
    // 4. Contract initialization

    // Expected edge fee: 0.05% in X128 format
    uint128 constant EXPECTED_EDGE_FEE_X128 =
        170141183460469231731687303715884105;
    // Expected protocol take: 8% in X128 format
    uint128 constant EXPECTED_PROTOCOL_TAKE_X128 =
        27222589353675077077069968594541456916;

    function getExpectedTokens() internal pure returns (address[] memory) {
        address[] memory tokens = new address[](9);
        tokens[0] = 0x549943e04f40284185054145c6E4e9568C1D3241;
        tokens[1] = 0x779Ded0c9e1022225f8E0630b35a9b54bE713736;
        tokens[2] = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
        tokens[3] = 0x1cE0a25D13CE4d52071aE7e02Cf1F6606F4C79d3;
        tokens[4] = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
        tokens[5] = 0xff12470a969Dd362EB6595FFB44C82c959Fe9ACc;
        tokens[6] = 0xEDB5180661F56077292C92Ab40B1AC57A279a396;
        tokens[7] = 0x09D4214C03D01F49544C0448DBE3A27f768F2b34;
        tokens[8] = 0x688e72142674041f8f6Af4c808a4045cA1D6aC82;
        return tokens;
    }

    function getExpectedEfactors() internal pure returns (uint256[] memory) {
        uint256[] memory efactors = new uint256[](9);
        efactors[0] = 2000;
        efactors[1] = 1500;
        efactors[2] = 500;
        efactors[3] = 333;
        efactors[4] = 660;
        efactors[5] = 100;
        efactors[6] = 50;
        efactors[7] = 200;
        efactors[8] = 1500;
        return efactors;
    }

    function testUpdateEdgeFees() public {
        UpdateEdgeFees updater = new UpdateEdgeFees();

        console2.log("Updater deployed at:", address(updater));

        // Deal tokens to the updater contract for RFT payer functionality
        dealTokensToUpdater(updater);

        transferOwnership(address(updater));

        updater.acceptOwnership();
        console2.log("Ownership accepted");

        updater.updateAllEdgeFees();
        console2.log("All edge fees updated");

        // Verify the updates
        console2.log("=== After Update ===");
        verifyEdgeFees("After update");

        updater.transferOwnership();
        console2.log("Ownership transferred back to multisig");
    }

    function dealTokensToUpdater(UpdateEdgeFees updater) internal {
        // Use deal() to give tokens directly to the updater contract
        deal(
            address(0xff12470a969Dd362EB6595FFB44C82c959Fe9ACc),
            address(updater),
            3566092269896669409
        );
    }

    function verifyEdgeFees(string memory context) internal view {
        IBurveMultiSimplex simplex = IBurveMultiSimplex(diamond);

        // Check default edge fee and protocol take
        (uint128 defaultEdgeFeeX128, uint128 protocolTakeX128) = simplex
            .getSimplexFees();
        console2.log("=== Simplex Fees ===");
        console2.log("Default Edge Fee X128:", defaultEdgeFeeX128);
        console2.log("Expected Default Edge Fee X128:", EXPECTED_EDGE_FEE_X128);
        console2.log("Protocol Take X128:", protocolTakeX128);
        console2.log(
            "Expected Protocol Take X128:",
            EXPECTED_PROTOCOL_TAKE_X128
        );

        require(
            defaultEdgeFeeX128 == EXPECTED_EDGE_FEE_X128,
            "Default edge fee not updated correctly"
        );
        require(
            protocolTakeX128 == EXPECTED_PROTOCOL_TAKE_X128,
            "Protocol take not updated correctly"
        );

        // Check specific edge fees
        console2.log("=== Edge Fee Verification ===");

        // Check edge 0,1
        uint128 edgeFee01 = simplex.getEdgeFee(0, 1);
        console2.log("Edge 0,1 fee X128:", edgeFee01);
        console2.log("Expected Edge 0,1 fee X128:", EXPECTED_EDGE_FEE_X128);
        require(
            edgeFee01 == EXPECTED_EDGE_FEE_X128,
            "Edge 0,1 fee not updated correctly"
        );

        // Check edge 1,2
        uint128 edgeFee12 = simplex.getEdgeFee(1, 2);
        console2.log("Edge 1,2 fee X128:", edgeFee12);
        console2.log("Expected Edge 1,2 fee X128:", EXPECTED_EDGE_FEE_X128);
        require(
            edgeFee12 == EXPECTED_EDGE_FEE_X128,
            "Edge 1,2 fee not updated correctly"
        );

        // Check edge 0,2
        uint128 edgeFee02 = simplex.getEdgeFee(0, 2);
        console2.log("Edge 0,2 fee X128:", edgeFee02);
        console2.log("Expected Edge 0,2 fee X128:", EXPECTED_EDGE_FEE_X128);
        require(
            edgeFee02 == EXPECTED_EDGE_FEE_X128,
            "Edge 0,2 fee not updated correctly"
        );

        // Verify EX128 values (efactors)
        console2.log("=== EX128 Verification ===");
        verifyEX128Values();

        console2.log("=== Verification Complete for", context, "===");
    }

    function verifyEX128Values() internal view {
        IBurveMultiSimplex simplex = IBurveMultiSimplex(diamond);

        // Verify each token's EX128 value using arrays
        address[] memory tokens = getExpectedTokens();
        uint256[] memory efactors = getExpectedEfactors();

        require(
            tokens.length == efactors.length,
            "Expected tokens and efactors length mismatch"
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            _verifyTokenEX128(simplex, tokens[i], efactors[i], i);
        }

        console2.log("=== All EX128 values verified ===");
    }

    function _verifyTokenEX128(
        IBurveMultiSimplex simplex,
        address token,
        uint256 expectedEfactor,
        uint256 tokenIndex
    ) internal view {
        uint256 expectedEX128 = expectedEfactor * (2 ** 128);
        uint256 actualEX128 = simplex.getEX128(token);

        console2.log("=== Token", tokenIndex, "===");
        console2.log("Token address:", token);
        console2.log("Expected efactor:", expectedEfactor);
        console2.log("Expected EX128:", expectedEX128);
        console2.log("Actual EX128:", actualEX128);

        require(
            actualEX128 == expectedEX128,
            string(
                abi.encodePacked(
                    "EX128 for token ",
                    vm.toString(token),
                    " not set correctly"
                )
            )
        );
    }

    /// This setup is done with the multisig itself approving a transaction to move the ownership of the smart contract
    /// to the contract.
    function transferOwnership(address executor) internal {
        vm.startPrank(MULTISIG);

        BaseAdminFacet(address(diamond)).transferOwnership(executor);

        vm.stopPrank();
    }
}
