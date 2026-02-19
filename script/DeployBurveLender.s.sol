// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BurveLender} from "../src/integrations/lender/BurveLender.sol";
import {BurveLooper} from "../src/integrations/looper/BurveLooper.sol";

contract DeployBurveLender is Script {
    address constant BERACHAIN_ROUTER =
        0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy BurveLender
        BurveLender lender = new BurveLender(BERACHAIN_ROUTER);
        console2.log("BurveLender deployed at:", address(lender));

        // Deploy BurveLooper
        BurveLooper looper = new BurveLooper(address(lender));
        console2.log("BurveLooper deployed at:", address(looper));

        // NOTE: After deployment, configure price feeds:
        // lender.setPriceFeed(USDC, chainlinkUsdcFeed, 6);
        // lender.setPriceFeed(USDT, chainlinkUsdtFeed, 6);
        // lender.setPriceFeed(HONEY, chainlinkHoneyFeed, 18);

        vm.stopBroadcast();
    }
}
