// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Create2Deployer {
    function deploy(
        bytes memory bytecode,
        bytes32 salt
    ) public returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
    }
}
