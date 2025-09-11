// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { console2 } from "forge-std/console2.sol";
import { SafeCast } from "Commons/Math/Cast.sol";
import { Auto165 } from "Commons/ERC/Auto165.sol";
import { RFTLib, RFTPayer } from "Commons/Util/RFT.sol";
import { TransferHelper } from "Commons/Util/TransferHelper.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IBurveMultiSimplex } from "../multi/interfaces/IBurveMultiSimplex.sol";
import { IBurveMultiValue } from "../multi/interfaces/IBurveMultiValue.sol";
import { FullMath } from "../FullMath.sol";
import { AdminLib } from "Commons/Util/Admin.sol";

interface IRewarder2 {
    function onDeposit(address user, uint256 mintedShares) external;
    function onWithdraw(address user, uint256 requestedSharesToBurn) external;
}

contract BRC20 is ERC20, RFTPayer, Auto165, IBurveMultiValue {
    IBurveMultiValue public immutable pool;
    IBurveMultiSimplex public immutable simplex;
    uint16 public immutable closureId;
    uint256 public constant MAX_TOKENS = 16;
    
    address public transient _recipient;
    address public transient _operator;
    bool public transient isCompounding;

    uint256 public totalShares;
    uint256 private _totalSupply;
    uint256 public totalValue;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // PoL (vault to recieve the fees and the vault fee take)
    address public immutable polVault;
    uint256 public immutable feeTakeX64;

    uint256 private constant MIN_DEAD_SHARES = 100;
    /// Thrown when the first mint is insufficient.
    error InsecureFirstMintAmount(uint256 shares);
    /// Thrown when attempting to queryValue using this contract
    error Noop();
    /// Thrown when attempting to re-enter the operations
    error NonReentrant();

    // Rewarder2 integration
    address public rewarder;

    // set the recipient as transient storage
    modifier storeRecipient(address recipient) {
        if (_recipient != address(0)) revert NonReentrant();
        _recipient = recipient;
        _operator = msg.sender;
        _;
        _recipient = address(0);
        _operator = address(0);
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _pool,
        uint16 _closureId,
        address _polVault,
        uint256 _feeTakeX64
    ) ERC20(_name, _symbol) {
        AdminLib.initOwner(msg.sender);
        pool = IBurveMultiValue(_pool);
        simplex = IBurveMultiSimplex(_pool);
        closureId = _closureId;
        polVault = _polVault;
        feeTakeX64 = _feeTakeX64;
    }

    function setRewarder(address _rewarder) external {
        AdminLib.validateOwner();
        rewarder = _rewarder;
    }

    /// @notice Override _update to handle rewarder calls for all token operations
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        
        // Skip rewarder calls for zero address operations (internal accounting)
        if (rewarder != address(0)) {
            if (from == address(0)) {
                // Mint operation - call onDeposit for the recipient
                IRewarder2(rewarder).onDeposit(to, value);
            } else if (to == address(0)) {
                // Burn operation - call onWithdraw for the sender
                IRewarder2(rewarder).onWithdraw(from, value);
            } else {
                IRewarder2(rewarder).onDeposit(to, value);
                IRewarder2(rewarder).onWithdraw(from, value);
            }
        }
    }

    /// closureId and bgtValue are hard-coded in this implementation, but remain here to conform to the interface.
    function addValue(
        address recipient,
        uint16,
        uint128 value,
        uint128,
        uint256[MAX_TOKENS] memory amountLimits
    ) external storeRecipient(recipient) returns (uint256[MAX_TOKENS] memory requiredBalances) {
        _compound();

        requiredBalances = pool.addValue(
            address(this),
            closureId,
            value,
            0,
            amountLimits
        );

        _mintShares(value);
    }

    /// Remove value by withdrawing pro-rata balances of each vertex in the closure.
    function removeValue(
        address recipient,
        uint16,
        uint128 shares,
        uint128,
        uint256[MAX_TOKENS] memory amountLimits
    ) external storeRecipient(recipient) returns (uint256[MAX_TOKENS] memory receivedBalances) {
        _compound();

        uint256 value = _burnShares(shares);

        receivedBalances = pool.removeValue(
            address(this),
            closureId,
            uint128(value),
            0,
            amountLimits
        );
    }

    /// Add an exact amount of value to a given closure by depositing a single token.
    function addValueSingle(
        address recipient,
        uint16,
        uint128 value,
        uint128,
        address token,
        uint128 maxRequired
    ) external storeRecipient(recipient) returns (uint256 requiredBalance) {
        _compound();

        requiredBalance = pool.addValueSingle(
            address(this),
            closureId,
            value,
            0,
            token,
            maxRequired
        );

        _mintShares(value);
    }

    /// Remove an exact amount of value from a given closure by withdrawing a single token.
    function removeValueSingle(
        address recipient,
        uint16,
        uint128 shares,
        uint128,
        address token,
        uint128 minReceive
    ) external storeRecipient(recipient) returns (uint256 removedBalance) {
        _compound();

        uint256 value = _burnShares(shares);

        removedBalance = pool.removeValueSingle(
            address(this),
            closureId,
            SafeCast.toUint128(value),
            0,
            token,
            minReceive
        );
    }

    /// Add an exact amount of a single token to add value to a given closure.
    function addSingleForValue(
        address recipient,
        uint16,
        address token,
        uint128 amount,
        uint256,
        uint128 minValue
    ) external storeRecipient(recipient) returns (uint256 valueReceived) {
        _compound();

        valueReceived = pool.addSingleForValue(
            address(this),
            closureId,
            token,
            amount,
            0,
            minValue
        );

        _mintShares(valueReceived);
    }

    /// Remove an exact amount of a single token to remove value from a given closure.
    function removeSingleForValue(
        address recipient,
        uint16,
        address token,
        uint128 amount,
        uint256,
        uint128 maxValue
    ) external storeRecipient(recipient) returns (uint256 valueGiven) {
        _compound();

        valueGiven = pool.removeSingleForValue(
            address(this),
            closureId,
            token,
            amount,
            0,
            maxValue
        );

        _burnShares(valueGiven);
    }

    /// Not implemented. Only appears to satisfy the IBurveMultiValue interface.
    function queryValue(
        address,
        uint16
    ) external pure returns (
        uint256,
        uint256,
        uint256[MAX_TOKENS] memory,
        uint256
    ) {
        revert Noop();
    }

    /// Compounds the position for everyone.
    function collectEarnings(
        address,
        uint16
    ) external returns (
        uint256[MAX_TOKENS] memory collectedBalances,
        uint256 collectedBgt
    ) {
        (collectedBalances, collectedBgt) = _compound();
    }

    function _mintShares(uint256 value) internal returns (uint256 shares) {
        if (totalShares == 0) {
            // If this is the first mint, it has to be dead shares, burned by giving it to this contract.
            shares = value;
            if (shares < MIN_DEAD_SHARES) {
                revert InsecureFirstMintAmount(shares);
            }
        } else {
            shares = FullMath.mulDiv(value, totalShares, totalValue);
        }
        totalValue += value;
        totalShares += shares;
        _mint(_recipient, shares);
    }

    function _burnShares(uint256 shares) internal returns (uint256 value) {
        value = FullMath.mulDiv(shares, totalValue, totalShares);
        totalValue -= value;
        totalShares -= shares;
        _burn(msg.sender, shares);
    }

    function _compound() internal returns (
        uint256[MAX_TOKENS] memory collectedBalances,
        uint256 collectedBgt
    ) {
        (collectedBalances, collectedBgt) = pool.collectEarnings(address(this), closureId);

        address[] memory tokens = simplex.getTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (collectedBalances[i] <= 0) continue;

            uint256 take;
            if(polVault != address(0)) {
                take  = FullMath.mulDiv(collectedBalances[i], feeTakeX64, 1 << 64);
                TransferHelper.safeTransfer(
                    tokens[i],
                    polVault,
                    take
                );
            }
            
            uint256 valueReceived = pool.addSingleForValue(
                address(this),
                closureId,
                tokens[i],
                SafeCast.toUint128(collectedBalances[i] - take),
                0,
                0
            );
            totalValue += valueReceived;
        }

        isCompounding = false;
    }

    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata data
    ) external returns (bytes memory) {
        require(msg.sender == address(pool), "Unauthorized");

        // collect fees returns data, we will deposit all of this back 
        if (data.length > 0) {
            isCompounding = true;
            return "";
        }

        if (isCompounding) {
            TransferHelper.safeTransfer(
                tokens[0], // we always singleAdd
                address(pool),
                SafeCast.toUint256(requests[0])
            );
            return "";
        }

        // add & remove 
        // _operator / _recipient 
        // we can either simplify to just use the msg.sender, or we need to add 
        // data tracking to tell the difference between deposit and withdraw.
        RFTLib.settle(_operator, tokens, requests, data);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            // depositing, forward to the pool
            if (requests[i] > 0) {
                // minting
                TransferHelper.safeTransfer(
                    tokens[i],
                    address(pool),
                    SafeCast.toUint256(requests[i])
                );
            }
        }
    }
}
