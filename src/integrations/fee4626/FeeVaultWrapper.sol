// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title FeeVaultWrapper
/// @notice ERC4626 wrapper that charges entry/exit fees and wraps another ERC4626 vault (e.g., Aave aTokens)
/// @dev Fees are charged in basis points (100 = 1%). Max fee is 1000 bps (10%).
/// The wrapper deposits user assets (minus fees) into the underlying vault and tracks shares.
contract FeeVaultWrapper is ERC4626, Ownable, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // ============ Constants ============

    uint256 private constant _BASIS_POINT_SCALE = 10000;
    uint256 private constant _MAX_FEE_BPS = 1000; // 10% max fee

    // ============ State Variables ============

    /// @notice Entry fee in basis points (charged on deposit)
    uint16 public entryFeeBps;

    /// @notice Exit fee in basis points (charged on withdrawal)
    uint16 public exitFeeBps;

    /// @notice Address that receives collected fees
    address public feeRecipient;

    /// @notice Underlying ERC4626 vault (e.g., Aave aToken)
    IERC4626 public immutable underlyingVault;

    // ============ Events ============

    event EntryFeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event ExitFeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event FeesCollected(address indexed recipient, uint256 amount);

    // ============ Errors ============

    error FeeTooHigh();
    error InvalidFeeRecipient();

    // ============ Constructor ============

    /// @notice Creates a new FeeVaultWrapper
    /// @param _underlyingVault The ERC4626 vault to wrap (e.g., Aave aToken)
    /// @param _name Name of the wrapper token
    /// @param _symbol Symbol of the wrapper token
    /// @param _feeRecipient Address to receive fees
    constructor(
        IERC4626 _underlyingVault,
        string memory _name,
        string memory _symbol,
        address _feeRecipient
    ) ERC4626(IERC20(_underlyingVault.asset())) ERC20(_name, _symbol) Ownable(msg.sender) {
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();

        underlyingVault = _underlyingVault;
        feeRecipient = _feeRecipient;

        // Start with 0% fees for safety
        entryFeeBps = 0;
        exitFeeBps = 0;

        // Approve underlying vault for max uint256 to save gas on deposits
        IERC20(_underlyingVault.asset()).forceApprove(address(_underlyingVault), type(uint256).max);
    }

    // ============ ERC4626 Overrides ============

    /// @notice Total assets under management (in underlying vault + any accumulated fees)
    function totalAssets() public view virtual override returns (uint256) {
        // Get our share balance in the underlying vault
        uint256 ourShares = underlyingVault.balanceOf(address(this));
        // Convert to assets
        return underlyingVault.convertToAssets(ourShares);
    }

    /// @notice Preview deposit with entry fee deducted
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        uint256 fee = _feeOnTotal(assets, entryFeeBps);
        uint256 assetsAfterFee = assets - fee;

        // Convert assets to shares in underlying vault
        uint256 underlyingShares = underlyingVault.previewDeposit(assetsAfterFee);

        // Convert underlying shares to our wrapper shares
        return _convertFromUnderlyingShares(underlyingShares, Math.Rounding.Floor);
    }

    /// @notice Preview mint with entry fee added
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        // Convert our wrapper shares to underlying shares
        uint256 underlyingShares = _convertToUnderlyingShares(shares, Math.Rounding.Ceil);

        // Get assets needed for underlying vault
        uint256 assets = underlyingVault.previewMint(underlyingShares);

        // Add entry fee
        return assets + _feeOnRaw(assets, entryFeeBps);
    }

    /// @notice Preview withdraw with exit fee added
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        uint256 fee = _feeOnRaw(assets, exitFeeBps);
        uint256 totalAssetsNeeded = assets + fee;

        // Convert to underlying shares needed
        uint256 underlyingShares = underlyingVault.previewWithdraw(totalAssetsNeeded);

        // Convert to our wrapper shares
        return _convertFromUnderlyingShares(underlyingShares, Math.Rounding.Ceil);
    }

    /// @notice Preview redeem with exit fee deducted
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        // Convert our wrapper shares to underlying shares
        uint256 underlyingShares = _convertToUnderlyingShares(shares, Math.Rounding.Floor);

        // Get assets from underlying vault
        uint256 assets = underlyingVault.previewRedeem(underlyingShares);

        // Deduct exit fee
        uint256 fee = _feeOnTotal(assets, exitFeeBps);
        return assets - fee;
    }

    /// @notice Deposit with entry fee charged
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override nonReentrant {
        // Calculate and transfer fee
        uint256 fee = _feeOnTotal(assets, entryFeeBps);
        uint256 assetsAfterFee = assets - fee;

        // Transfer assets from caller
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);

        // Transfer fee to recipient
        if (fee > 0) {
            SafeERC20.safeTransfer(IERC20(asset()), feeRecipient, fee);
        }

        // Deposit remaining assets into underlying vault
        uint256 underlyingShares = underlyingVault.deposit(assetsAfterFee, address(this));

        // Mint wrapper shares to receiver
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /// @notice Withdraw with exit fee charged
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override nonReentrant {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // Calculate total assets needed (including fee)
        uint256 fee = _feeOnRaw(assets, exitFeeBps);
        uint256 totalAssetsNeeded = assets + fee;

        // Burn wrapper shares
        _burn(owner, shares);

        // Withdraw from underlying vault
        uint256 underlyingShares = _convertToUnderlyingShares(shares, Math.Rounding.Ceil);
        underlyingVault.redeem(underlyingShares, address(this), address(this));

        // Transfer assets to receiver
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        // Transfer fee to recipient
        if (fee > 0) {
            SafeERC20.safeTransfer(IERC20(asset()), feeRecipient, fee);
        }

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    // ============ Internal Helpers ============

    /// @notice Convert wrapper shares to underlying vault shares
    function _convertToUnderlyingShares(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 totalShares = totalSupply();
        uint256 totalUnderlyingShares = underlyingVault.balanceOf(address(this));

        if (totalShares == 0) {
            return shares; // 1:1 on first deposit
        }

        return shares.mulDiv(totalUnderlyingShares, totalShares, rounding);
    }

    /// @notice Convert underlying vault shares to wrapper shares
    function _convertFromUnderlyingShares(uint256 underlyingShares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 totalShares = totalSupply();
        uint256 totalUnderlyingShares = underlyingVault.balanceOf(address(this));

        if (totalUnderlyingShares == 0) {
            return underlyingShares; // 1:1 on first deposit
        }

        return underlyingShares.mulDiv(totalShares, totalUnderlyingShares, rounding);
    }

    /// @notice Calculate fee on raw assets (fee not yet included)
    function _feeOnRaw(uint256 assets, uint256 feeBasisPoints) private pure returns (uint256) {
        return assets.mulDiv(feeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }

    /// @notice Calculate fee on total assets (fee already included)
    function _feeOnTotal(uint256 assets, uint256 feeBasisPoints) private pure returns (uint256) {
        return assets.mulDiv(feeBasisPoints, feeBasisPoints + _BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }

    // ============ Admin Functions ============

    /// @notice Set entry fee (charged on deposits)
    /// @param newFeeBps New fee in basis points (100 = 1%)
    function setEntryFee(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > _MAX_FEE_BPS) revert FeeTooHigh();

        uint16 oldFeeBps = entryFeeBps;
        entryFeeBps = newFeeBps;

        emit EntryFeeUpdated(oldFeeBps, newFeeBps);
    }

    /// @notice Set exit fee (charged on withdrawals)
    /// @param newFeeBps New fee in basis points (100 = 1%)
    function setExitFee(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > _MAX_FEE_BPS) revert FeeTooHigh();

        uint16 oldFeeBps = exitFeeBps;
        exitFeeBps = newFeeBps;

        emit ExitFeeUpdated(oldFeeBps, newFeeBps);
    }

    /// @notice Set fee recipient address
    /// @param newRecipient New fee recipient address
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert InvalidFeeRecipient();

        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;

        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    // ============ View Functions ============

    /// @notice Get the underlying vault address
    function getUnderlyingVault() external view returns (address) {
        return address(underlyingVault);
    }

    /// @notice Get current fee configuration
    function getFeeConfig() external view returns (uint16 entry, uint16 exit, address recipient) {
        return (entryFeeBps, exitFeeBps, feeRecipient);
    }
}
