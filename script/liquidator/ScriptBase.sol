// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

/// @title DealScript
/// @notice Script base that provides deal() for ERC20 tokens on Anvil.
///         Forge's Script doesn't include StdCheats.deal, so we implement it
///         directly using stdstore (the same approach forge-std uses).
abstract contract DealScript is Script {
    using stdStorage for StdStorage;

    /// @notice Set an ERC20 token balance for an address.
    function _deal(address token, address to, uint256 amount) internal {
        stdstore.target(token).sig(0x70a08231).with_key(to).checked_write(amount);
    }
}
