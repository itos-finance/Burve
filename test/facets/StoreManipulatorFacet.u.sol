// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../../src/multi/Store.sol";
import {Simplex} from "../../src/multi/Simplex.sol";
import {MAX_TOKENS} from "../../src/multi/Constants.sol";

contract StoreManipulatorFacet {
    function setProtocolEarnings(
        uint256[MAX_TOKENS] memory _protocolEarnings
    ) external {
        Store.simplex().protocolEarnings = _protocolEarnings;
    }
}
