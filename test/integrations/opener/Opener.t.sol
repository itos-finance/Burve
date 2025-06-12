// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;
import {BurveForkableTest} from "../Fork.u.sol";
import {Opener} from "../../../src/integrations/opener/Opener.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {Create2Deployer} from "../../utils/Create2Deployer.sol";

contract TestOpener is BurveForkableTest {
    Opener opener;
    Create2Deployer create2Deployer;
    bytes32 internal constant OPENER_SALT = keccak256("opener-test-salt");

    function deployOpenerDeterministically() internal returns (Opener) {
        if (address(create2Deployer) == address(0)) {
            create2Deployer = new Create2Deployer();
        }
        bytes memory bytecode = type(Opener).creationCode;
        address addr = create2Deployer.deploy(bytecode, OPENER_SALT);
        return Opener(addr);
    }

    function testTwoTokenOpener() public {
        opener = deployOpenerDeterministically();
        console2.log(address(opener));

        address[] memory tokens = new address[](2);
        tokens[0] = 0x549943e04f40284185054145c6E4e9568C1D3241;
        tokens[1] = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;

        console2.log("bfore");
        deal(tokens[0], address(this), 5e18);
        console2.log("after");
        IERC20(tokens[0]).approve(address(opener), 5e18);
        // deal(address(this), tokens[1], 5e18);

        bytes[] memory txData = new bytes[](1);
        txData[
            0
        ] = "0xd46cadbc000000000000000000000000549943e04f40284185054145c6e4e9568c1d32410000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000fcbd14dc51f0a4d49d5e53c2e0950e0bc26d0dce000000000000000000000000000000000000000c9f2c9cd04675000000000000000000000000000000000000000000000000000c7edcce72084ffd70a3d70a3d0000000000000000000000006b00e4570c187440fd6899d7aa4adfe5ff199e4a0000000000000000000000000000000000000000000000000000000000000120000000000000000000000000062a2b0eea575f659a1aaf18c1df5d93e0528245000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000caFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce00000000000000000000000000000000000000000c9f2c9cd04675000000000000000000000000000000000000000000000000000000044ed4feaadff080000000000000000000000000000000000000000000000000007bd3c697d3a73800000001549943e04f40284185054145c6E4e9568C1D324101ffff11A4aFef880F5cE1f63c9fb48F661E27F8B4216401549943e04f40284185054145c6E4e9568C1D3241062a2b0eea575f659a1aaf18c1df5d93e052824500000000000000000000000000000000000000000000";
        uint16 closureId = 3;
        uint256 nonSwappingAmount = 1e6;
        uint256 bgtPercentX256 = 0;
        uint256[MAX_TOKENS] memory amountLimits;
        opener.mint(
            diamond,
            tokens,
            txData,
            closureId,
            nonSwappingAmount,
            bgtPercentX256,
            amountLimits
        );
    }

    function testThreeTokenOpener() public {}
}
