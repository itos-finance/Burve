// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";

import {BurveForkableTest} from "../../test/integrations/Fork.u.sol";
import {Add_MEAD_RUSD_PYUSD} from "./Add_MEAD_RUSD_PYUSD.sol";
import {AdminLib, BaseAdminFacet} from "Commons/Util/Admin.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {RFTLib, RFTPayer} from "Commons/Util/RFT.sol";
import {TransferHelper} from "../../src/TransferHelper.sol";
import {Auto165} from "Commons/ERC/Auto165.sol";

contract FAdd_MEAD_RUSD_PYUSD is BurveForkableTest, RFTPayer, Auto165 {
    address[3] private addedTokens = [
        0xEDB5180661F56077292C92Ab40B1AC57A279a396,
        0x09D4214C03D01F49544C0448DBE3A27f768F2b34,
        0x688e72142674041f8f6Af4c808a4045cA1D6aC82
    ];
    address constant MULTISIG = 0x9293f9FFC43F6fce06290285919541E963D87F51;

    constructor() RFTPayer() {}

    function testAdd_MEAD_RUSD_PYUSD() public {
        Add_MEAD_RUSD_PYUSD executor = new Add_MEAD_RUSD_PYUSD();
        // Add_MEAD_RUSD_PYUSD executor = Add_MEAD_RUSD_PYUSD(
        //     0xeA5A3388D0254C9B684AB074674661493774BA0E
        // );

        transferOwnership(address(executor));

        fundExecutor(address(executor));

        // fundFork();

        executor.acceptOwnership();

        vm.startSnapshotGas("deployMEAD");

        executor.deployMEAD();
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("MEAD", gasUsed);

        vm.startSnapshotGas("deployRUSD");
        executor.deployRUSD();
        gasUsed = vm.stopSnapshotGas();
        console2.log("rUSD", gasUsed);

        vm.startSnapshotGas("deployPYUSD1");
        executor.deployPYUSD();
        gasUsed = vm.stopSnapshotGas();
        console2.log("PYUSD1", gasUsed);

        vm.startSnapshotGas("initializeClosure");
        uint16 minClosure = 1 << 6;
        uint16 maxClosure = 1 << 9;
        uint16 offset = 4;
        for (uint16 min = minClosure; min < maxClosure; min += offset) {
            executor.initializeClosure(
                min,
                min + offset > maxClosure ? maxClosure : min + offset
            );
        }
        gasUsed = vm.stopSnapshotGas();

        executor.transferOwnership();

        getBalances(address(executor));

        addValue();
    }

    function addValue() internal {
        uint256[16] memory limits;
        valueFacet.addValue(
            address(0xbe7dC5cC7977ac378ead410869D6c96f1E6C773e),
            (1 << 9) - 1,
            513104573203253618,
            0,
            limits
        );
    }

    /// This setup is done with the multisig itself approving a transaction to move the ownership of the smart contract
    /// to the contract.
    function transferOwnership(address executor) internal {
        vm.startPrank(0xeA5A3388D0254C9B684AB074674661493774BA0E);

        BaseAdminFacet(address(diamond)).transferOwnership(executor);

        vm.stopPrank();
    }

    function fundExecutor(address executor) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            deal(address(tokens[i]), executor, 10e28);
        }

        for (uint256 j = 0; j < addedTokens.length; j++) {
            deal(addedTokens[j], executor, 10e28);
        }
    }

    function getBalances(address executor) internal view {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(address(tokens[i])).balanceOf(executor);
            console2.log(address(tokens[i]));
            console2.log(balance);
        }

        for (uint256 j = 0; j < addedTokens.length; j++) {
            uint256 balance = IERC20(address(addedTokens[j])).balanceOf(
                executor
            );
            console2.log(address(addedTokens[j]));
            console2.log(balance);
        }
    }

    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata
    ) external returns (bytes memory) {
        for (uint256 i = 0; i < tokens.length; i++) {
            deal(tokens[i], address(this), uint256(requests[i]));
            TransferHelper.safeTransfer(
                tokens[i],
                msg.sender,
                uint256(requests[i])
            );
        }
    }
}
