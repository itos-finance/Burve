// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Burve} from "../src/single/Burve.sol";
import {IUniswapV3Pool} from "../src/single/integrations/kodiak/IUniswapV3Pool.sol";
import {IKodiakIsland} from "../src/single/integrations/kodiak/IKodiakIsland.sol";
import {TickRange} from "../src/single/TickRange.sol";
import {IStationProxy} from "../src/single/IStationProxy.sol";
import {NullStationProxy} from "../test/single/NullStationProxy.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeploySingleBurve is Script {
    using stdJson for string;

    // Core contracts
    Burve public burve;
    IStationProxy public stationProxy;
    IUniswapV3Pool public pool;
    IKodiakIsland public island;

    // Bartio deployment addresses
    address constant POOL_ADDRESS = 0x8a960A6e5f224D0a88BaD10463bDAD161b68C144; // HONEY/WBERA Pool
    address constant ISLAND_ADDRESS =
        0x12C195768f65F282EA5F1B5C42755FBc910B0D8F;

    // Token addresses
    address constant HONEY = 0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03;
    address constant WBERA = 0x7507c1dc16935B82698e4C63f2746A2fCf994dF8;

    // Pool configuration
    int24 constant POOL_TICK_SPACING = 60;
    int24 constant ISLAND_LOWER_TICK = -47820;
    int24 constant ISLAND_UPPER_TICK = -1800;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Initialize pool and island interfaces
        pool = IUniswapV3Pool(POOL_ADDRESS);
        island = IKodiakIsland(ISLAND_ADDRESS);

        // Verify pool and island are compatible
        require(address(island.pool()) == POOL_ADDRESS, "Island pool mismatch");

        // Deploy station proxy
        stationProxy = new NullStationProxy();

        // Setup ranges for Burve

        // TickRange[] memory ranges = new TickRange[](2);
        // // Island range using the specific Bartio parameters
        // ranges[0] = TickRange(ISLAND_LOWER_TICK, ISLAND_UPPER_TICK);
        // // V3 range centered around current tick
        // ranges[1] = TickRange(-107820, 58200);

        // // Setup weights for ranges
        // uint128[] memory weights = new uint128[](2);
        // weights[0] = 2; // 66% weight to island
        // weights[1] = 1; // 33% weight to v3 range

        // // Deploy Burve
        // burve = new Burve(
        //     POOL_ADDRESS,
        //     ISLAND_ADDRESS,
        //     address(stationProxy),
        //     ranges,
        //     weights
        // );

        // // Log deployed addresses and configuration
        // console2.log("Deployments:");
        // console2.log("Pool:", POOL_ADDRESS);
        // console2.log("Island:", ISLAND_ADDRESS);
        // console2.log("StationProxy:", address(stationProxy));
        // console2.log("Burve:", address(burve));

        // Write deployment addresses to JSON file
        string memory json = vm.readFile("script/deployments.json");
        // json = json.serialize("bartio.pool", POOL_ADDRESS);
        // json = json.serialize("bartio.island", ISLAND_ADDRESS);
        json = json.serialize("bartio.stationProxy", address(stationProxy));
        // json = json.serialize("bartio.burve", address(burve));
        vm.writeFile("script/deployments.json", json);

        vm.stopBroadcast();
    }
}
