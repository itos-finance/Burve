// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BurveLender} from "../src/integrations/lender/BurveLender.sol";
import {BurveLooper} from "../src/integrations/looper/BurveLooper.sol";
import {DolomiteOracleAdapter} from "../src/integrations/lender/DolomiteOracleAdapter.sol";

contract DeployBurveLender is Script {
    address constant BERACHAIN_ROUTER =
        0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;

    // Dolomite OracleAggregatorV2 on Berachain mainnet
    address constant DOLOMITE_ORACLE =
        0xa150Ef2D5827dB283321D15d62d5D07fB41d636E;

    // Burve Diamond on Berachain mainnet
    address constant BURVE_DIAMOND =
        0x46B4e28088cA7f73a3bB4BAdfcAb38B0E58e53F0;

    // Berachain token addresses
    address constant USDC = 0x549943e04f40284185054145c6E4e9568C1D3241;
    address constant USDT = 0x779Ded0c9e1022225f8E0630b35a9b54bE713736;
    address constant HONEY = 0xFcBd14Dc51F0A4d49D5e53C2A0BfA8E95BaB1De0;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy BurveLender
        BurveLender lender = new BurveLender(BERACHAIN_ROUTER);
        console2.log("BurveLender deployed at:", address(lender));

        // 2. Deploy BurveLooper
        BurveLooper looper = new BurveLooper(address(lender));
        console2.log("BurveLooper deployed at:", address(looper));

        // 3. Deploy DolomiteOracleAdapters (one per token)
        DolomiteOracleAdapter usdcOracle = new DolomiteOracleAdapter(DOLOMITE_ORACLE, USDC, 6);
        DolomiteOracleAdapter usdtOracle = new DolomiteOracleAdapter(DOLOMITE_ORACLE, USDT, 6);
        DolomiteOracleAdapter honeyOracle = new DolomiteOracleAdapter(DOLOMITE_ORACLE, HONEY, 18);
        console2.log("USDC Oracle Adapter:", address(usdcOracle));
        console2.log("USDT Oracle Adapter:", address(usdtOracle));
        console2.log("HONEY Oracle Adapter:", address(honeyOracle));

        // 4. Configure BurveLender
        lender.setPoolAllowed(BURVE_DIAMOND, true);
        lender.setPriceFeed(USDC, address(usdcOracle), 6);
        lender.setPriceFeed(USDT, address(usdtOracle), 6);
        lender.setPriceFeed(HONEY, address(honeyOracle), 18);

        console2.log("Configuration complete.");

        vm.stopBroadcast();
    }
}
