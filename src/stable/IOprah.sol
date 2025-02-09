// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface IOprah {
    function distribute(address owner, uint256 balance) external;
}
