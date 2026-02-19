// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {LoanPosition, LendingPool} from "./BurveLenderStorage.sol";
import {InterestRateModel} from "./InterestRateModel.sol";
import {PositionValuer} from "./PositionValuer.sol";
import {PositionProxy} from "./PositionProxy.sol";
import {IBurveMultiValue} from "../../multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../multi/interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "../../multi/facets/ValueTokenFacet.sol";
import {IAdjustor} from "../adjustor/IAdjustor.sol";
import {MAX_TOKENS} from "../../multi/Constants.sol";
import {FullMath} from "../../FullMath.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

/// @title BurveLender
/// @notice Lending protocol for Burve value positions. Users deposit value positions as collateral,
///         borrow tokens from lending pools, and can be liquidated if health factor drops below 1.
///         Each position is held by a CREATE2 proxy to prevent position merging in Burve's AssetBook.
contract BurveLender is ReentrancyGuardTransient, Ownable {
    using SafeERC20 for IERC20;

    // --- Constants ---
    uint256 public constant MAX_LTV = 80e16;            // 80% (1e18 = 100%)
    uint256 public constant LIQUIDATION_LTV = 85e16;     // 85%
    uint256 public constant LIQUIDATION_PENALTY = 5e16;   // 5%
    uint256 public constant LIQUIDATION_CALLER_BONUS = 3e16; // 3% to caller
    uint256 public constant MIN_POSITION_USD = 100e18;    // $100 minimum
    uint256 public constant PRECISION = 1e18;
    uint256 internal constant X128 = 1 << 128;

    // --- State ---
    uint256 public nextPositionId;

    /// positionId => LoanPosition
    mapping(uint256 => LoanPosition) public positions;
    /// positionId => token => principal borrowed
    mapping(uint256 => mapping(address => uint256)) public tokenBorrows;
    /// positionId => token => borrow index snapshot at last accrual
    mapping(uint256 => mapping(address => uint256)) public borrowIndex;

    /// token => LendingPool
    mapping(address => LendingPool) public lendingPools;
    /// token => user => LP shares
    mapping(address => mapping(address => uint256)) public lpShares;

    /// token => Chainlink price feed
    mapping(address => address) public priceFeeds;
    /// token => decimals cache
    mapping(address => uint8) public tokenDecimals;

    /// The swap router for liquidation swaps (e.g. OogaBooga).
    address public router;

    // --- Events ---
    event CollateralDeposited(uint256 indexed positionId, address indexed borrower, address pool, uint16 closureId, uint256 value, uint256 bgtValue);
    event CollateralWithdrawn(uint256 indexed positionId, uint256 value, uint256 bgtValue);
    event Borrowed(uint256 indexed positionId, address indexed token, uint256 amount);
    event Repaid(uint256 indexed positionId, address indexed token, uint256 amount);
    event LiquidityDeposited(address indexed token, address indexed lp, uint256 amount, uint256 shares);
    event LiquidityWithdrawn(address indexed token, address indexed lp, uint256 amount, uint256 shares);
    event Liquidated(uint256 indexed positionId, address indexed liquidator, uint256 collateralValueUSD, uint256 debtValueUSD);
    event EarningsCollected(uint256 indexed positionId, address indexed recipient);
    event PriceFeedSet(address indexed token, address indexed feed);

    // --- Errors ---
    error NotPositionOwner();
    error PositionNotFound();
    error ExceedsMaxLTV();
    error PositionHealthy();
    error BelowMinPosition();
    error InsufficientLiquidity();
    error InsufficientShares();
    error ZeroAmount();
    error RouterFailure();
    error NoPriceFeed();
    error WithdrawalWouldLiquidate();

    constructor(address _router) Ownable(msg.sender) {
        router = _router;
    }

    // ============================================================
    //                     ADMIN FUNCTIONS
    // ============================================================

    /// @notice Set a Chainlink price feed for a token.
    function setPriceFeed(address token, address feed, uint8 decimals) external onlyOwner {
        priceFeeds[token] = feed;
        tokenDecimals[token] = decimals;
        emit PriceFeedSet(token, feed);
    }

    /// @notice Update the swap router address.
    function setRouter(address _router) external onlyOwner {
        router = _router;
    }

    // ============================================================
    //                     BORROWER FUNCTIONS
    // ============================================================

    /// @notice Deposit a Burve value position as collateral.
    /// @dev Transfers value from msg.sender to a new CREATE2 proxy via ValueTokenFacet.
    /// @param pool The Burve diamond address.
    /// @param closureId The closure ID of the position.
    /// @param value The value units to deposit.
    /// @param bgtValue The BGT value units to deposit.
    /// @return positionId The ID of the newly created position.
    function depositCollateral(
        address pool,
        uint16 closureId,
        uint256 value,
        uint256 bgtValue
    ) external nonReentrant returns (uint256 positionId) {
        if (value == 0) revert ZeroAmount();

        positionId = nextPositionId++;

        // Deploy a CREATE2 proxy for this position
        address proxy = _deployProxy(positionId);

        // Transfer value position from user to proxy
        ValueTokenFacet(pool).transferFrom(
            msg.sender,
            proxy,
            closureId,
            value,
            bgtValue
        );

        // Validate minimum position value
        uint256 posUSD = _collateralValueUSD(pool, closureId, value, bgtValue);
        if (posUSD < MIN_POSITION_USD) revert BelowMinPosition();

        // Store position
        LoanPosition storage pos = positions[positionId];
        pos.borrower = msg.sender;
        pos.pool = pool;
        pos.closureId = closureId;
        pos.proxy = proxy;
        pos.depositedValue = value;
        pos.depositedBgtValue = bgtValue;

        emit CollateralDeposited(positionId, msg.sender, pool, closureId, value, bgtValue);
    }

    /// @notice Add more value to an existing collateral position.
    /// @dev The additional value is transferred from msg.sender to the position's proxy.
    /// @param positionId The position to add collateral to.
    /// @param value Additional value units.
    /// @param bgtValue Additional BGT value units.
    function addCollateral(
        uint256 positionId,
        uint256 value,
        uint256 bgtValue
    ) external nonReentrant {
        if (value == 0 && bgtValue == 0) revert ZeroAmount();
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower != msg.sender) revert NotPositionOwner();

        ValueTokenFacet(pos.pool).transferFrom(
            msg.sender,
            pos.proxy,
            pos.closureId,
            value,
            bgtValue
        );

        pos.depositedValue += value;
        pos.depositedBgtValue += bgtValue;

        emit CollateralDeposited(positionId, msg.sender, pos.pool, pos.closureId, value, bgtValue);
    }

    /// @notice Borrow tokens against a collateralized position.
    /// @param positionId The position to borrow against.
    /// @param token The token to borrow.
    /// @param amount The amount to borrow.
    function borrow(
        uint256 positionId,
        address token,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower != msg.sender) revert NotPositionOwner();

        // Accrue interest on this token's lending pool
        _accrueInterest(token);

        LendingPool storage pool = lendingPools[token];
        if (pool.totalDeposited - pool.totalBorrowed < amount) revert InsufficientLiquidity();

        // Settle any existing borrow for this token on this position
        _settlePositionBorrow(positionId, token);

        // Record the new borrow
        tokenBorrows[positionId][token] += amount;
        borrowIndex[positionId][token] = pool.borrowIndexX128;
        pool.totalBorrowed += amount;

        // Check LTV constraint AFTER the borrow
        uint256 colUSD = collateralValueUSD(positionId);
        uint256 debtUSD = borrowValueUSD(positionId);
        if (debtUSD * PRECISION > colUSD * MAX_LTV) revert ExceedsMaxLTV();

        // Transfer borrowed tokens to the borrower
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Borrowed(positionId, token, amount);
    }

    /// @notice Repay borrowed tokens.
    /// @param positionId The position to repay.
    /// @param token The token to repay.
    /// @param amount The amount to repay (use type(uint256).max to repay all).
    function repay(
        uint256 positionId,
        address token,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower == address(0)) revert PositionNotFound();

        _accrueInterest(token);
        _settlePositionBorrow(positionId, token);

        uint256 owed = tokenBorrows[positionId][token];
        uint256 repayAmount = amount > owed ? owed : amount;

        tokenBorrows[positionId][token] -= repayAmount;
        borrowIndex[positionId][token] = lendingPools[token].borrowIndexX128;
        lendingPools[token].totalBorrowed -= repayAmount;

        IERC20(token).safeTransferFrom(msg.sender, address(this), repayAmount);

        emit Repaid(positionId, token, repayAmount);
    }

    /// @notice Withdraw value from a collateralized position.
    /// @dev Reverts if the withdrawal would push the position below the max LTV.
    /// @param positionId The position to withdraw from.
    /// @param value The value units to withdraw.
    /// @param bgtValue The BGT value units to withdraw.
    function withdrawCollateral(
        uint256 positionId,
        uint256 value,
        uint256 bgtValue
    ) external nonReentrant {
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower != msg.sender) revert NotPositionOwner();
        if (value == 0 && bgtValue == 0) revert ZeroAmount();

        pos.depositedValue -= value;
        pos.depositedBgtValue -= bgtValue;

        // Transfer value from proxy back to user
        PositionProxy(pos.proxy).execute(
            pos.pool,
            abi.encodeCall(
                ValueTokenFacet.transfer,
                (msg.sender, pos.closureId, value, bgtValue)
            )
        );

        // Check health after withdrawal
        if (pos.depositedValue > 0) {
            uint256 colUSD = collateralValueUSD(positionId);
            uint256 debtUSD = borrowValueUSD(positionId);
            if (debtUSD > 0 && debtUSD * PRECISION > colUSD * MAX_LTV) {
                revert WithdrawalWouldLiquidate();
            }
        }

        emit CollateralWithdrawn(positionId, value, bgtValue);
    }

    // ============================================================
    //                     LENDER (LP) FUNCTIONS
    // ============================================================

    /// @notice Deposit tokens into a lending pool to earn interest.
    /// @param token The token to deposit.
    /// @param amount The amount to deposit.
    function depositLiquidity(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _accrueInterest(token);

        LendingPool storage pool = lendingPools[token];

        // Calculate shares
        uint256 shares;
        if (pool.totalShares == 0) {
            shares = amount;
        } else {
            shares = FullMath.mulDiv(amount, pool.totalShares, pool.totalDeposited);
        }

        pool.totalDeposited += amount;
        pool.totalShares += shares;
        lpShares[token][msg.sender] += shares;

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit LiquidityDeposited(token, msg.sender, amount, shares);
    }

    /// @notice Withdraw tokens from a lending pool.
    /// @param token The token to withdraw.
    /// @param shares The number of LP shares to redeem.
    function withdrawLiquidity(address token, uint256 shares) external nonReentrant {
        if (shares == 0) revert ZeroAmount();
        if (lpShares[token][msg.sender] < shares) revert InsufficientShares();

        _accrueInterest(token);

        LendingPool storage pool = lendingPools[token];

        uint256 amount = FullMath.mulDiv(shares, pool.totalDeposited, pool.totalShares);

        uint256 available = pool.totalDeposited - pool.totalBorrowed;
        if (amount > available) revert InsufficientLiquidity();

        pool.totalDeposited -= amount;
        pool.totalShares -= shares;
        lpShares[token][msg.sender] -= shares;

        IERC20(token).safeTransfer(msg.sender, amount);

        emit LiquidityWithdrawn(token, msg.sender, amount, shares);
    }

    // ============================================================
    //                     LIQUIDATION
    // ============================================================

    /// @notice Liquidate an unhealthy position.
    /// @dev Calls removeValue on Burve via the proxy, swaps tokens via router, repays debt.
    /// @param positionId The position to liquidate.
    /// @param txData Swap calldata for each non-debt token (router calls).
    /// @param debtTokens The tokens that are borrowed (to repay).
    function liquidate(
        uint256 positionId,
        bytes[MAX_TOKENS] memory txData,
        address[] calldata debtTokens
    ) external nonReentrant {
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower == address(0)) revert PositionNotFound();

        // Accrue interest on all debt tokens
        for (uint256 i = 0; i < debtTokens.length; i++) {
            _accrueInterest(debtTokens[i]);
            _settlePositionBorrow(positionId, debtTokens[i]);
        }

        // Check that position is unhealthy
        uint256 colUSD = collateralValueUSD(positionId);
        uint256 debtUSD = borrowValueUSD(positionId);
        if (debtUSD * PRECISION <= colUSD * LIQUIDATION_LTV) revert PositionHealthy();

        // Remove all value from Burve via proxy
        uint256[MAX_TOKENS] memory minAmounts;
        PositionProxy(pos.proxy).execute(
            pos.pool,
            abi.encodeCall(
                IBurveMultiValue.removeValue,
                (pos.proxy, pos.closureId, uint128(pos.depositedValue), uint128(pos.depositedBgtValue), minAmounts)
            )
        );

        // Get pool tokens
        address[] memory poolTokens = IBurveMultiSimplex(pos.pool).getTokens();

        // Transfer all received tokens from proxy to this contract
        for (uint256 i = 0; i < poolTokens.length; i++) {
            uint256 bal = IERC20(poolTokens[i]).balanceOf(pos.proxy);
            if (bal > 0) {
                PositionProxy(pos.proxy).transferToken(poolTokens[i], address(this), bal);
            }
        }

        // Swap non-debt tokens into debt tokens via router
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (txData[i].length == 0) continue;
            uint256 bal = IERC20(poolTokens[i]).balanceOf(address(this));
            if (bal == 0) continue;
            IERC20(poolTokens[i]).forceApprove(router, bal);
            (bool success, ) = router.call(txData[i]);
            if (!success) revert RouterFailure();
        }

        // Repay debts and calculate amounts
        uint256 totalDebtRepaid;
        for (uint256 i = 0; i < debtTokens.length; i++) {
            uint256 owed = tokenBorrows[positionId][debtTokens[i]];
            if (owed == 0) continue;

            lendingPools[debtTokens[i]].totalBorrowed -= owed;
            tokenBorrows[positionId][debtTokens[i]] = 0;
            totalDebtRepaid += owed;
        }

        // Calculate liquidation penalty and bonus
        // 3% to caller, 2% to protocol (retained in contract)
        uint256 callerBonus;
        for (uint256 i = 0; i < debtTokens.length; i++) {
            uint256 bal = IERC20(debtTokens[i]).balanceOf(address(this));
            uint256 owed = totalDebtRepaid; // simplified: single debt token most common
            if (bal > owed) {
                uint256 surplus = bal - owed;
                uint256 bonus = FullMath.mulDiv(surplus, LIQUIDATION_CALLER_BONUS, LIQUIDATION_PENALTY);
                if (bonus > surplus) bonus = surplus;
                callerBonus += bonus;
                // Send bonus to liquidator
                IERC20(debtTokens[i]).safeTransfer(msg.sender, bonus);
                // Remainder after protocol cut goes to borrower
                uint256 protocolCut = surplus - bonus;
                uint256 borrowerReturn = 0;
                if (protocolCut > FullMath.mulDiv(surplus, LIQUIDATION_PENALTY - LIQUIDATION_CALLER_BONUS, LIQUIDATION_PENALTY)) {
                    borrowerReturn = protocolCut - FullMath.mulDiv(surplus, LIQUIDATION_PENALTY - LIQUIDATION_CALLER_BONUS, LIQUIDATION_PENALTY);
                    protocolCut -= borrowerReturn;
                }
                if (borrowerReturn > 0) {
                    IERC20(debtTokens[i]).safeTransfer(pos.borrower, borrowerReturn);
                }
            }
        }

        // Clean up position
        pos.depositedValue = 0;
        pos.depositedBgtValue = 0;

        emit Liquidated(positionId, msg.sender, colUSD, debtUSD);
    }

    // ============================================================
    //                     FEE PASS-THROUGH
    // ============================================================

    /// @notice Collect Burve trading fee earnings from a position and send to recipient.
    /// @param positionId The position to collect from.
    /// @param recipient Where to send the earnings.
    function collectPositionEarnings(
        uint256 positionId,
        address recipient
    ) external nonReentrant {
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower != msg.sender) revert NotPositionOwner();

        // Collect earnings via the proxy
        PositionProxy(pos.proxy).execute(
            pos.pool,
            abi.encodeCall(
                IBurveMultiValue.collectEarnings,
                (pos.proxy, pos.closureId)
            )
        );

        // Transfer all collected tokens from proxy to recipient
        address[] memory poolTokens = IBurveMultiSimplex(pos.pool).getTokens();
        for (uint256 i = 0; i < poolTokens.length; i++) {
            uint256 bal = IERC20(poolTokens[i]).balanceOf(pos.proxy);
            if (bal > 0) {
                PositionProxy(pos.proxy).transferToken(poolTokens[i], recipient, bal);
            }
        }

        emit EarningsCollected(positionId, recipient);
    }

    // ============================================================
    //                     VIEW FUNCTIONS
    // ============================================================

    /// @notice Get the health factor for a position.
    ///         Health factor = (collateralUSD * LIQUIDATION_LTV) / debtUSD
    ///         Returns type(uint256).max if no debt.
    function healthFactor(uint256 positionId) external view returns (uint256) {
        uint256 debtUSD = borrowValueUSD(positionId);
        if (debtUSD == 0) return type(uint256).max;

        uint256 colUSD = collateralValueUSD(positionId);
        return FullMath.mulDiv(colUSD, LIQUIDATION_LTV, debtUSD);
    }

    /// @notice Get the USD value of a position's collateral.
    function collateralValueUSD(uint256 positionId) public view returns (uint256) {
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower == address(0)) return 0;
        return _collateralValueUSD(pos.pool, pos.closureId, pos.depositedValue, pos.depositedBgtValue);
    }

    /// @notice Get the total USD value of a position's borrows.
    function borrowValueUSD(uint256 positionId) public view returns (uint256 totalUSD) {
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower == address(0)) return 0;

        address[] memory poolTokens = IBurveMultiSimplex(pos.pool).getTokens();
        for (uint256 i = 0; i < poolTokens.length; i++) {
            address token = poolTokens[i];
            uint256 principal = tokenBorrows[positionId][token];
            if (principal == 0) continue;

            // Calculate current owed with accrued interest
            uint256 owed = _currentBorrow(positionId, token);
            uint8 decimals = tokenDecimals[token];
            address feed = priceFeeds[token];
            if (feed == address(0)) continue;
            totalUSD += PositionValuer.valueTokenUSD(token, owed, decimals, feed);
        }
    }

    /// @notice Get the current amount owed for a specific token borrow.
    function currentBorrow(uint256 positionId, address token) external view returns (uint256) {
        return _currentBorrow(positionId, token);
    }

    // ============================================================
    //                     INTERNAL FUNCTIONS
    // ============================================================

    /// @dev Deploy a CREATE2 proxy for a position.
    function _deployProxy(uint256 positionId) internal returns (address proxy) {
        bytes32 salt = keccak256(abi.encodePacked(positionId));
        proxy = address(new PositionProxy{salt: salt}());
    }

    /// @dev Compute the CREATE2 address for a position's proxy.
    function getProxyAddress(uint256 positionId) external view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(positionId));
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(type(PositionProxy).creationCode))
        )))));
    }

    /// @dev Accrue interest on a lending pool.
    function _accrueInterest(address token) internal {
        LendingPool storage pool = lendingPools[token];
        if (pool.lastAccrualTimestamp == 0) {
            pool.borrowIndexX128 = X128;
            pool.supplyIndexX128 = X128;
            pool.lastAccrualTimestamp = block.timestamp;
            return;
        }

        uint256 timeDelta = block.timestamp - pool.lastAccrualTimestamp;
        if (timeDelta == 0) return;

        // Update borrow index
        uint256 borrowMultiplier = InterestRateModel.getBorrowMultiplierX128(
            pool.totalBorrowed,
            pool.totalDeposited,
            timeDelta
        );
        uint256 oldBorrowIndex = pool.borrowIndexX128;
        pool.borrowIndexX128 = FullMath.mulDiv(oldBorrowIndex, borrowMultiplier, X128);

        // Calculate interest earned and add to totalBorrowed and totalDeposited
        uint256 interestEarned = FullMath.mulDiv(
            pool.totalBorrowed,
            borrowMultiplier - X128,
            X128
        );
        uint256 reserveCut = FullMath.mulDiv(interestEarned, InterestRateModel.RESERVE_FACTOR, PRECISION);
        pool.totalBorrowed += interestEarned;
        pool.totalDeposited += interestEarned - reserveCut;

        // Update supply index
        if (pool.totalShares > 0 && pool.totalDeposited > 0) {
            uint256 supplyMultiplier = InterestRateModel.getSupplyMultiplierX128(
                pool.totalBorrowed - interestEarned, // use pre-accrual for consistency
                pool.totalDeposited - (interestEarned - reserveCut),
                timeDelta
            );
            pool.supplyIndexX128 = FullMath.mulDiv(pool.supplyIndexX128, supplyMultiplier, X128);
        }

        pool.lastAccrualTimestamp = block.timestamp;
    }

    /// @dev Settle a position's borrow for a specific token to the current index.
    function _settlePositionBorrow(uint256 positionId, address token) internal {
        uint256 principal = tokenBorrows[positionId][token];
        if (principal == 0) return;

        uint256 oldIndex = borrowIndex[positionId][token];
        uint256 currentIndex = lendingPools[token].borrowIndexX128;

        if (oldIndex == 0 || oldIndex == currentIndex) return;

        // Update principal to reflect accrued interest
        uint256 newPrincipal = FullMath.mulDiv(principal, currentIndex, oldIndex);
        tokenBorrows[positionId][token] = newPrincipal;
        borrowIndex[positionId][token] = currentIndex;
    }

    /// @dev Calculate the current borrow amount including accrued interest (view).
    function _currentBorrow(uint256 positionId, address token) internal view returns (uint256) {
        uint256 principal = tokenBorrows[positionId][token];
        if (principal == 0) return 0;

        uint256 oldIndex = borrowIndex[positionId][token];
        uint256 currentIndex = lendingPools[token].borrowIndexX128;

        if (oldIndex == 0 || currentIndex == 0) return principal;

        // Also need to account for unaccrued interest since last accrual
        LendingPool storage pool = lendingPools[token];
        uint256 timeDelta = block.timestamp - pool.lastAccrualTimestamp;
        if (timeDelta > 0) {
            uint256 multiplier = InterestRateModel.getBorrowMultiplierX128(
                pool.totalBorrowed,
                pool.totalDeposited,
                timeDelta
            );
            currentIndex = FullMath.mulDiv(currentIndex, multiplier, X128);
        }

        return FullMath.mulDiv(principal, currentIndex, oldIndex);
    }

    /// @dev Internal view to compute collateral USD value.
    function _collateralValueUSD(
        address pool,
        uint16 closureId,
        uint256 value,
        uint256 bgtValue
    ) internal view returns (uint256) {
        return PositionValuer.valuePositionUSD(pool, closureId, value, bgtValue, priceFeeds);
    }
}
