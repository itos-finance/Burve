// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Burve} from "../src/Burve.sol";

contract BurveDeployScript is Script {
    Burve public burve;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // burve = new Burve();

        vm.stopBroadcast();
    }
}
