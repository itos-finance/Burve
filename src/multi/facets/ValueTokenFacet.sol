// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

/// An ERC20 interface for the Value token which is mint and burned by unstaking/staking value.
/// TODO: Add to Diamond when ready.
contract ValueTokenFacet is ERC20 {
    // TODO handle naming.
    constructor() ERC20("Make name later", "HALP") {}

    /*
    function mint(uint256 valueAmount, uint16 _cid) external {}

    function burn(uint256 valueAmount, uint16 _cid) external {}
    */
}
