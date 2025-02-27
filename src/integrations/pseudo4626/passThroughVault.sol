// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

// import {AdminLib} from "Commons/Util/Admin.sol";
// import {ERC4626} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
// import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
// import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
// import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

// contract PassThroughVault is ERC4626 {
//     IERC4626 public inner;

//     constructor(
//         ERC20 asset,
//         string memory name,
//         string memory symbol,
//         IERC4626 _inner
//     ) ERC20(name, symbol) ERC4626(asset) {
//         AdminLib.initOwner(msg.sender);
//         inner = _inner;
//     }

//     /// The only unique functionality of this vault is it can transfer ownership to another contract.
//     /// This is used in migrating from one vault to another

//     // Overrides to show how much we've deposited in the inner vault.
//     function totalAssets() public view virtual override returns (uint256) {
//         return inner.maxWithdraw(address(this));
//     }

//     // Pass through
//     function convertToShares(
//         uint256 assets
//     ) public view virtual returns (uint256) {
//         return inner.convertToShares(assets);
//     }

//     // Pass through
//     function convertToAssets(
//         uint256 shares
//     ) public view virtual returns (uint256) {
//         return inner.convertToAssets(shares);
//     }

//     // Pass through
//     function maxDeposit(
//         address recipient
//     ) public view virtual returns (uint256) {
//         return inner.maxDeposit(recipient);
//     }

//     // Pass through
//     function maxMint(address recipient) public view virtual returns (uint256) {
//         return inner.maxDeposit(recipient);
//     }

//     /** @dev See {IERC4626-maxWithdraw}. */
//     function maxWithdraw(address owner) public view virtual returns (uint256) {
//         return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
//     }

//     /** @dev See {IERC4626-maxRedeem}. */
//     function maxRedeem(address owner) public view virtual returns (uint256) {
//         return balanceOf(owner);
//     }

//     /** @dev See {IERC4626-previewDeposit}. */
//     function previewDeposit(
//         uint256 assets
//     ) public view virtual returns (uint256) {
//         return _convertToShares(assets, Math.Rounding.Floor);
//     }

//     /** @dev See {IERC4626-previewMint}. */
//     function previewMint(uint256 shares) public view virtual returns (uint256) {
//         return _convertToAssets(shares, Math.Rounding.Ceil);
//     }

//     /** @dev See {IERC4626-previewWithdraw}. */
//     function previewWithdraw(
//         uint256 assets
//     ) public view virtual returns (uint256) {
//         return _convertToShares(assets, Math.Rounding.Ceil);
//     }

//     /** @dev See {IERC4626-previewRedeem}. */
//     function previewRedeem(
//         uint256 shares
//     ) public view virtual returns (uint256) {
//         return _convertToAssets(shares, Math.Rounding.Floor);
//     }

//     /** @dev See {IERC4626-deposit}. */
//     function deposit(
//         uint256 assets,
//         address receiver
//     ) public virtual returns (uint256) {
//         uint256 maxAssets = maxDeposit(receiver);
//         if (assets > maxAssets) {
//             revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
//         }

//         uint256 shares = previewDeposit(assets);
//         _deposit(_msgSender(), receiver, assets, shares);

//         return shares;
//     }

//     /** @dev See {IERC4626-mint}. */
//     function mint(
//         uint256 shares,
//         address receiver
//     ) public virtual returns (uint256) {
//         uint256 maxShares = maxMint(receiver);
//         if (shares > maxShares) {
//             revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
//         }

//         uint256 assets = previewMint(shares);
//         _deposit(_msgSender(), receiver, assets, shares);

//         return assets;
//     }

//     /** @dev See {IERC4626-withdraw}. */
//     function withdraw(
//         uint256 assets,
//         address receiver,
//         address owner
//     ) public virtual returns (uint256) {
//         uint256 maxAssets = maxWithdraw(owner);
//         if (assets > maxAssets) {
//             revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
//         }

//         uint256 shares = previewWithdraw(assets);
//         _withdraw(_msgSender(), receiver, owner, assets, shares);

//         return shares;
//     }

//     /** @dev See {IERC4626-redeem}. */
//     function redeem(
//         uint256 shares,
//         address receiver,
//         address owner
//     ) public virtual returns (uint256) {
//         uint256 maxShares = maxRedeem(owner);
//         if (shares > maxShares) {
//             revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
//         }

//         uint256 assets = previewRedeem(shares);
//         _withdraw(_msgSender(), receiver, owner, assets, shares);

//         return assets;
//     }

//     /**
//      * @dev Internal conversion function (from assets to shares) with support for rounding direction.
//      */
//     function _convertToShares(
//         uint256 assets,
//         Math.Rounding rounding
//     ) internal view virtual returns (uint256) {
//         return
//             assets.mulDiv(
//                 totalSupply() + 10 ** _decimalsOffset(),
//                 totalAssets() + 1,
//                 rounding
//             );
//     }

//     /**
//      * @dev Internal conversion function (from shares to assets) with support for rounding direction.
//      */
//     function _convertToAssets(
//         uint256 shares,
//         Math.Rounding rounding
//     ) internal view virtual returns (uint256) {
//         return
//             shares.mulDiv(
//                 totalAssets() + 1,
//                 totalSupply() + 10 ** _decimalsOffset(),
//                 rounding
//             );
//     }

//     /**
//      * @dev Deposit/mint common workflow.
//      */
//     function _deposit(
//         address caller,
//         address receiver,
//         uint256 assets,
//         uint256 shares
//     ) internal virtual {
//         // If _asset is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
//         // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
//         // calls the vault, which is assumed not malicious.
//         //
//         // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
//         // assets are transferred and before the shares are minted, which is a valid state.
//         // slither-disable-next-line reentrancy-no-eth
//         SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
//         _mint(receiver, shares);

//         emit Deposit(caller, receiver, assets, shares);
//     }

//     /**
//      * @dev Withdraw/redeem common workflow.
//      */
//     function _withdraw(
//         address caller,
//         address receiver,
//         address owner,
//         uint256 assets,
//         uint256 shares
//     ) internal virtual {
//         if (caller != owner) {
//             _spendAllowance(owner, caller, shares);
//         }

//         // If _asset is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
//         // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
//         // calls the vault, which is assumed not malicious.
//         //
//         // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
//         // shares are burned and after the assets are transferred, which is a valid state.
//         _burn(owner, shares);
//         SafeERC20.safeTransfer(_asset, receiver, assets);

//         emit Withdraw(caller, receiver, owner, assets, shares);
//     }
// }
