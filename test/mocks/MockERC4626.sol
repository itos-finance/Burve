// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockERC4626 is ERC4626 {
    ERC20 private immutable _asset;

    constructor(
        ERC20 asset,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC4626(asset) {
        _asset = asset;
    }

    function burnAssets(uint256 amount) public {
        // Burn some amount of assets from this vault.
        _asset.transfer(address(0xDEADBEEF), amount);
    }
}

contract MockERC4626WithdrawlLimited is MockERC4626 {
    uint256 public withdrawLimit;

    constructor(
        ERC20 asset,
        string memory name,
        string memory symbol,
        uint256 _withdrawLimit
    ) MockERC4626(asset, name, symbol) {
        withdrawLimit = _withdrawLimit;
    }

    // Override maxWithdraw with the withdrawal limit.
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 maxAssets = super.maxWithdraw(owner);
        return maxAssets > withdrawLimit ? withdrawLimit : maxAssets;
    }
}
