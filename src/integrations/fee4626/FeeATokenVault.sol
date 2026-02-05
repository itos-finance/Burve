// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {IAToken} from "@aave-v3-core/interfaces/IAToken.sol";
import {IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPoolAddressesProvider.sol";

/**
 * @title FeeATokenVault
 * @author Burve Finance
 * @notice ERC4626 vault wrapping Aave V3 aTokens with entry/exit fees
 * @dev Charges fees in basis points on deposits and withdrawals
 */
contract FeeATokenVault is ERC4626, Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant _BASIS_POINT_SCALE = 10000;
    uint256 private constant _MAX_FEE_BPS = 1000; // 10% max

    IPool public immutable AAVE_POOL;
    IAToken public immutable ATOKEN;
    uint16 public immutable REFERRAL_CODE;

    uint16 public entryFeeBps;
    uint16 public exitFeeBps;
    address public feeRecipient;

    event EntryFeeUpdated(uint16 oldFee, uint16 newFee);
    event ExitFeeUpdated(uint16 oldFee, uint16 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event FeeCollected(address indexed from, uint256 amount, bool isEntry);

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        IPoolAddressesProvider poolAddressesProvider,
        uint16 referralCode_,
        address initialOwner,
        address feeRecipient_,
        uint16 entryFeeBps_,
        uint16 exitFeeBps_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(initialOwner) {
        require(feeRecipient_ != address(0), "ZERO_FEE_RECIPIENT");
        require(entryFeeBps_ <= _MAX_FEE_BPS, "ENTRY_FEE_TOO_HIGH");
        require(exitFeeBps_ <= _MAX_FEE_BPS, "EXIT_FEE_TOO_HIGH");

        AAVE_POOL = IPool(poolAddressesProvider.getPool());
        REFERRAL_CODE = referralCode_;

        // Get aToken address for this asset
        address aTokenAddress = AAVE_POOL.getReserveData(address(asset_)).aTokenAddress;
        require(aTokenAddress != address(0), "ASSET_NOT_SUPPORTED");
        ATOKEN = IAToken(aTokenAddress);

        feeRecipient = feeRecipient_;
        entryFeeBps = entryFeeBps_;
        exitFeeBps = exitFeeBps_;

        // Approve Aave pool to spend underlying
        IERC20(asset_).approve(address(AAVE_POOL), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        PREVIEW FUNCTIONS WITH FEES
    //////////////////////////////////////////////////////////////*/

    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        uint256 fee = _feeOnTotal(assets, entryFeeBps);
        return super.previewDeposit(assets - fee);
    }

    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        uint256 assets = super.previewMint(shares);
        return assets + _feeOnRaw(assets, entryFeeBps);
    }

    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        uint256 fee = _feeOnRaw(assets, exitFeeBps);
        return super.previewWithdraw(assets + fee);
    }

    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        uint256 assets = super.previewRedeem(shares);
        return assets - _feeOnTotal(assets, exitFeeBps);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        // Calculate and take entry fee
        uint256 fee = _feeOnTotal(assets, entryFeeBps);
        uint256 assetsAfterFee = assets - fee;

        // Transfer assets from caller
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);

        // Supply assets (minus fee) to Aave
        AAVE_POOL.supply(asset(), assetsAfterFee, address(this), REFERRAL_CODE);

        // Mint shares to receiver
        _mint(receiver, shares);

        // Transfer fee to recipient
        if (fee > 0 && feeRecipient != address(0)) {
            SafeERC20.safeTransfer(IERC20(asset()), feeRecipient, fee);
            emit FeeCollected(caller, fee, true);
        }

        emit Deposit(caller, receiver, assetsAfterFee, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        // Calculate fee and total to withdraw from Aave
        uint256 fee = _feeOnRaw(assets, exitFeeBps);
        uint256 totalAssets = assets + fee;

        // Burn shares from owner
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);

        // Withdraw total from Aave to this contract
        AAVE_POOL.withdraw(asset(), totalAssets, address(this));

        // Send requested assets to receiver
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        // Send fee to recipient
        if (fee > 0 && feeRecipient != address(0)) {
            SafeERC20.safeTransfer(IERC20(asset()), feeRecipient, fee);
            emit FeeCollected(owner, fee, false);
        }

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTING OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view virtual override returns (uint256) {
        // Our assets are held as aTokens in the Aave pool
        return ATOKEN.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setEntryFee(uint16 newFeeBps) external onlyOwner {
        require(newFeeBps <= _MAX_FEE_BPS, "FEE_TOO_HIGH");
        uint16 oldFee = entryFeeBps;
        entryFeeBps = newFeeBps;
        emit EntryFeeUpdated(oldFee, newFeeBps);
    }

    function setExitFee(uint16 newFeeBps) external onlyOwner {
        require(newFeeBps <= _MAX_FEE_BPS, "FEE_TOO_HIGH");
        uint16 oldFee = exitFeeBps;
        exitFeeBps = newFeeBps;
        emit ExitFeeUpdated(oldFee, newFeeBps);
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "ZERO_ADDRESS");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                        FEE CALCULATION HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fee to add to raw amount (mint/withdraw)
    function _feeOnRaw(uint256 assets, uint256 feeBasisPoints) private pure returns (uint256) {
        return assets.mulDiv(feeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }

    /// @dev Fee part of total amount (deposit/redeem)
    function _feeOnTotal(uint256 assets, uint256 feeBasisPoints) private pure returns (uint256) {
        return assets.mulDiv(feeBasisPoints, feeBasisPoints + _BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }
}
