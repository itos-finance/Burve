// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;
import {BurveForkableTest} from "../Fork.u.sol";
import {Opener} from "../../../src/integrations/opener/Opener.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {Create2Deployer} from "../../utils/Create2Deployer.sol";
import {IOBRouter} from "../../../src/integrations/opener/IOBRouter.sol";

contract TestOpener is BurveForkableTest {
    Opener opener;
    Create2Deployer create2Deployer;
    bytes32 internal constant OPENER_SALT = keccak256("opener-test-salt");

    function deployOpenerDeterministically() internal returns (Opener) {
        if (address(create2Deployer) == address(0)) {
            create2Deployer = new Create2Deployer();
        }
        bytes memory bytecode = abi.encodePacked(
            type(Opener).creationCode,
            abi.encode(0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7)
        );
        address addr = create2Deployer.deploy(bytecode, OPENER_SALT);
        return Opener(addr);
    }

    function testTwoTokenOpener() public {
        opener = deployOpenerDeterministically();

        deal(tokens[0], address(this), 5e18);
        IERC20(tokens[0]).approve(address(opener), 5e18);
        IOBRouter.swapTokenInfo memory info = IOBRouter.swapTokenInfo({
            inputToken: address(0x549943e04f40284185054145c6E4e9568C1D3241),
            inputAmount: 1000000000000000000,
            outputToken: address(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce),
            outputQuote: 11988462483865600,
            outputMin: 9919685778590269,
            outputReceiver: address(0x0eDEd3901a62e8ef4764B61eEdCB2108F35b91e7)
        });

        bytes[MAX_TOKENS] memory params;
        params[1] = abi.encodeWithSelector(
            IOBRouter.swap.selector,
            info,
            hex"FCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce00000000000000000000000000000000000000000c9f2c9cd046750000000000000000000000000000000000000000000000000000000437b99bb57bc4000000000000000000000000000000000000000000000000000099c6b851f0542000000001549943e04f40284185054145c6E4e9568C1D324101ffff11A4aFef880F5cE1f63c9fb48F661E27F8B4216401549943e04f40284185054145c6E4e9568C1D3241062a2b0eea575f659a1aaf18c1df5d93e0528245",
            address(0x062a2B0eeA575f659a1aaf18c1DF5D93E0528245),
            2
        );

        uint16 closureId = 3;
        uint256 bgtPercentX256 = 0;
        uint256[MAX_TOKENS] memory amountLimits;
        opener.mint(
            diamond,
            0,
            1e18,
            params,
            closureId,
            bgtPercentX256,
            amountLimits,
            0
        );
    }

    function testThreeTokenOpener() public {}
}
