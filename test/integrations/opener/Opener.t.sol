// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;
import {BurveForkableTest} from "../Fork.u.sol";
import {Opener} from "../../../src/integrations/opener/Opener.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {Create2Deployer} from "../../utils/Create2Deployer.sol";
import {IOBRouter} from "../../../src/integrations/opener/IOBRouter.sol";
import {FullMath} from "../../../src/FullMath.sol";

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

        address inputToken = address(
            0x0555E30da8f98308EdB960aa94C0Db47230d2B9c
        );
        uint256 inputAmount = 100000000;
        address outputToken = address(
            0x541FD749419CA806a8bc7da8ac23D346f2dF8B77
        );
        uint256 outputQuote = 999949888810858131;
        uint256 outputMin = 989950389922749549;
        address outputReceiver = address(
            0x3FFaA9331633e3d8A97eaC109c4086645a8d659d
        );

        deal(inputToken, address(this), 5e18);
        IERC20(inputToken).approve(address(opener), 5e18);

        IOBRouter.swapTokenInfo memory info = IOBRouter.swapTokenInfo({
            inputToken: inputToken,
            inputAmount: inputAmount,
            outputToken: outputToken,
            outputQuote: outputQuote,
            outputMin: outputMin,
            outputReceiver: outputReceiver
        });

        bytes[MAX_TOKENS] memory params;
        params[1] = abi.encodeWithSelector(
            IOBRouter.swap.selector,
            info,
            hex"541FD749419CA806a8bc7da8ac23D346f2dF8B77010000000000000000000000000000000000000000000000000ddfeb59662d8d2c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000db54e0a597c5300010555E30da8f98308EdB960aa94C0Db47230d2B9c01ffff09BE09E71BDc7b8a50A05F7291920590505e3C7744cbef1b65399065c2de2c495971e90466ff38f2d000000000000000000000001e541FD749419CA806a8bc7da8ac23D346f2dF8B77062a2b0eea575f659a1aaf18c1df5d93e0528245",
            address(0x062a2B0eeA575f659a1aaf18c1DF5D93E0528245),
            2
        );

        uint16 closureId = 6;
        uint256 bgtPercentX256 = 0;
        uint256[MAX_TOKENS] memory amountLimits;
        opener.mint(
            diamond,
            inputToken,
            2e8,
            params,
            closureId,
            bgtPercentX256,
            amountLimits,
            0
        );
    }

    function testThreeTokenOpener() public {}
}
