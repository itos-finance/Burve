// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PositionProxy
/// @notice Lightweight CREATE2 proxy that holds a single user's Burve value position.
///         Each proxy has a unique address in Burve's AssetBook, preventing position merging
///         when multiple users deposit through Lender.
///         Only the Lender (deployer) can call execute() on this proxy.
contract PositionProxy {
    using SafeERC20 for IERC20;

    address public immutable lender;

    error OnlyLender();

    constructor() {
        lender = msg.sender;
    }

    /// @notice Execute an arbitrary call on behalf of Lender.
    /// @dev Only callable by the lender contract.
    /// @param target The target contract to call.
    /// @param data The calldata to send.
    /// @return result The return data from the call.
    function execute(address target, bytes calldata data) external returns (bytes memory result) {
        if (msg.sender != lender) revert OnlyLender();
        bool success;
        (success, result) = target.call(data);
        if (!success) {
            // Bubble up revert reason
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice Transfer tokens out of this proxy back to Lender or another recipient.
    /// @dev Only callable by the lender contract.
    /// @param token The ERC20 token to transfer.
    /// @param to The recipient address.
    /// @param amount The amount to transfer.
    function transferToken(address token, address to, uint256 amount) external {
        if (msg.sender != lender) revert OnlyLender();
        IERC20(token).safeTransfer(to, amount);
    }
}
