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
            inputToken: address(0),
            inputAmount: 0,
            outputToken: address(0),
            outputQuote: 0,
            outputMin: 0,
            outputReceiver: address(0)
        });

        Opener.OogaboogaParams[MAX_TOKENS] memory params;
        params[1] = Opener.OogaboogaParams({
            info: info,
            pathDefinition: abi.encode(),
            executor: address(0x1),
            referralCode: 0
        });
        uint16 closureId = 3;
        uint256 nonSwappingAmount = 1e6;
        uint256 bgtPercentX256 = 0;
        uint256[MAX_TOKENS] memory amountLimits;
        opener.mint(
            diamond,
            0,
            2e18,
            params,
            closureId,
            bgtPercentX256,
            amountLimits,
            0
        );
    }

    function testThreeTokenOpener() public {}
}
