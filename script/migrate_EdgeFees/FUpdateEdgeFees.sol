// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {BurveForkableTest} from "../../test/integrations/Fork.u.sol";
import {UpdateEdgeFees} from "./UpdateEdgeFees.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {IBurveMultiSimplex} from "../../src/multi/interfaces/IBurveMultiSimplex.sol";

contract FUpdateEdgeFees is BurveForkableTest {
    address constant MULTISIG = 0x9293f9FFC43F6fce06290285919541E963D87F51;

    // Expected edge fee: 0.005% in X128 format
    uint128 constant EXPECTED_EDGE_FEE_X128 =
        17014118346046923988514818429550592;
    // Expected protocol take: 8% in X128 format
    uint128 constant EXPECTED_PROTOCOL_TAKE_X128 =
        27222589353675077077069968594541456916;

    function testUpdateEdgeFees() public {
        UpdateEdgeFees updater = new UpdateEdgeFees();

        console2.log("Updater deployed at:", address(updater));

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

        // Check edge 7,8 (if they exist)
        uint8 numVertices = simplex.getNumVertices();
        console2.log("Number of vertices:", numVertices);

        if (numVertices > 8) {
            uint128 edgeFee78 = simplex.getEdgeFee(7, 8);
            console2.log("Edge 7,8 fee X128:", edgeFee78);
            console2.log("Expected Edge 7,8 fee X128:", EXPECTED_EDGE_FEE_X128);
            require(
                edgeFee78 == EXPECTED_EDGE_FEE_X128,
                "Edge 7,8 fee not updated correctly"
            );
        } else {
            console2.log(
                "Edge 7,8 does not exist (only",
                numVertices,
                "vertices)"
            );
        }

        console2.log("=== Verification Complete for", context, "===");
    }

    /// This setup is done with the multisig itself approving a transaction to move the ownership of the smart contract
    /// to the contract.
    function transferOwnership(address executor) internal {
        vm.startPrank(MULTISIG);

        BaseAdminFacet(address(diamond)).transferOwnership(executor);

        vm.stopPrank();
    }
}
