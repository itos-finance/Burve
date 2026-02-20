// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {LoanPosition, LendingPool} from "./LenderStorage.sol";
import {InterestRateModel} from "./InterestRateModel.sol";
import {PositionValuer} from "./PositionValuer.sol";
import {PositionProxy} from "./PositionProxy.sol";
import {IBurveMultiValue} from "../../multi/interfaces/IBurveMultiValue.sol";
import {IBurveMultiSimplex} from "../../multi/interfaces/IBurveMultiSimplex.sol";
import {ValueTokenFacet} from "../../multi/facets/ValueTokenFacet.sol";
import {MAX_TOKENS} from "../../multi/Constants.sol";
import {FullMath} from "../../FullMath.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

/// @title Lender
/// @notice Lending protocol for Burve value positions. Users deposit value positions as collateral,
///         borrow tokens from lending pools, and can be liquidated if health factor drops below 1.
///         Each position is held by a CREATE2 proxy to prevent position merging in Burve's AssetBook.
contract Lender is ReentrancyGuardTransient, Ownable {
    using SafeERC20 for IERC20;

    // --- Constants ---
    uint256 public constant MAX_LTV = 80e16;             // 80% (1e18 = 100%)
    uint256 public constant LIQUIDATION_LTV = 85e16;     // 85%
    uint256 public constant LIQUIDATION_BONUS = 5e16;    // 5% bonus to liquidator
    uint256 public constant MIN_POSITION_USD = 100e18;   // $100 minimum
    uint256 public constant PRECISION = 1e18;
    uint256 internal constant X128 = 1 << 128;

    // --- State ---
    uint256 public nextPositionId;

    /// positionId => LoanPosition
    mapping(uint256 => LoanPosition) public positions;
    /// positionId => token => principal borrowed (current after last settle)
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
    /// token => collateral factor (1e18 = 100%, 0 = default 100%)
    mapping(address => uint256) public collateralFactors;

    /// Allowlisted Burve pool addresses
    mapping(address => bool) public allowedPools;

    /// Authorized looper contracts that can create positions on behalf of users
    mapping(address => bool) public authorizedLoopers;

    // --- Events ---
    event CollateralDeposited(uint256 indexed positionId, address indexed borrower, address pool, uint16 closureId, uint256 value, uint256 bgtValue);
    event CollateralWithdrawn(uint256 indexed positionId, uint256 value, uint256 bgtValue);
    event Borrowed(uint256 indexed positionId, address indexed token, uint256 amount);
    event Repaid(uint256 indexed positionId, address indexed token, uint256 amount);
    event LiquidityDeposited(address indexed token, address indexed lp, uint256 amount, uint256 shares);
    event LiquidityWithdrawn(address indexed token, address indexed lp, uint256 amount, uint256 shares);
    event Liquidated(uint256 indexed positionId, address indexed liquidator, address debtToken, uint256 repaidAmount, uint256 seizedValue);
    event EarningsCollected(uint256 indexed positionId, address indexed recipient);
    event PoolAllowed(address indexed pool, bool allowed);
    event PriceFeedSet(address indexed token, address indexed feed);
    event CollateralFactorSet(address indexed token, uint256 factor);
    event LooperAuthorized(address indexed looper, bool authorized);

    // --- Errors ---
    error NotPositionOwner();
    error PositionNotFound();
    error ExceedsMaxLTV();
    error PositionHealthy();
    error BelowMinPosition();
    error InsufficientLiquidity();
    error InsufficientShares();
    error ZeroAmount();
    error NoPriceFeed();
    error PoolNotAllowed();
    error InvalidCollateralFactor();
    error ExcessRepayment();
    error NotAuthorizedLooper();

    constructor() Ownable(msg.sender) {}

    // ============================================================
    //                     ADMIN FUNCTIONS
    // ============================================================

    function setPriceFeed(address token, address feed, uint8 decimals) external onlyOwner {
        priceFeeds[token] = feed;
        tokenDecimals[token] = decimals;
        emit PriceFeedSet(token, feed);
    }

    function setCollateralFactor(address token, uint256 factor) external onlyOwner {
        if (factor > PRECISION) revert InvalidCollateralFactor();
        collateralFactors[token] = factor;
        emit CollateralFactorSet(token, factor);
    }

    function setPoolAllowed(address pool, bool allowed) external onlyOwner {
        allowedPools[pool] = allowed;
        emit PoolAllowed(pool, allowed);
    }

    function setLooperAuthorized(address looper, bool authorized) external onlyOwner {
        authorizedLoopers[looper] = authorized;
        emit LooperAuthorized(looper, authorized);
    }

    // ============================================================
    //                     BORROWER FUNCTIONS
    // ============================================================

    /// @notice Deposit a Burve value position as collateral.
    /// @param pool The Burve diamond address (must be allowlisted).
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
        if (!allowedPools[pool]) revert PoolNotAllowed();

        positionId = nextPositionId++;
        address proxy = _deployProxy(positionId);

        // Transfer value position from user to proxy
        ValueTokenFacet(pool).transferFrom(msg.sender, proxy, closureId, value, bgtValue);

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

    /// @notice Deposit collateral on behalf of another user (only authorized loopers).
    /// @dev The looper must have already transferred value to itself, then approves this contract.
    function depositCollateralFor(
        address borrower,
        address pool,
        uint16 closureId,
        uint256 value,
        uint256 bgtValue
    ) external nonReentrant returns (uint256 positionId) {
        if (value == 0) revert ZeroAmount();
        if (!allowedPools[pool]) revert PoolNotAllowed();
        if (!authorizedLoopers[msg.sender]) revert NotAuthorizedLooper();

        positionId = nextPositionId++;
        address proxy = _deployProxy(positionId);

        // Transfer value from the looper (msg.sender) to proxy
        ValueTokenFacet(pool).transferFrom(msg.sender, proxy, closureId, value, bgtValue);

        uint256 posUSD = _collateralValueUSD(pool, closureId, value, bgtValue);
        if (posUSD < MIN_POSITION_USD) revert BelowMinPosition();

        LoanPosition storage pos = positions[positionId];
        pos.borrower = borrower; // The actual user, not the looper
        pos.pool = pool;
        pos.closureId = closureId;
        pos.proxy = proxy;
        pos.depositedValue = value;
        pos.depositedBgtValue = bgtValue;

        emit CollateralDeposited(positionId, borrower, pool, closureId, value, bgtValue);
    }

    /// @notice Add more value to an existing collateral position.
    function addCollateral(uint256 positionId, uint256 value, uint256 bgtValue) external nonReentrant {
        if (value == 0 && bgtValue == 0) revert ZeroAmount();
        LoanPosition storage pos = positions[positionId];
        _requireOwnerOrLooper(pos.borrower);

        ValueTokenFacet(pos.pool).transferFrom(msg.sender, pos.proxy, pos.closureId, value, bgtValue);

        pos.depositedValue += value;
        pos.depositedBgtValue += bgtValue;

        emit CollateralDeposited(positionId, pos.borrower, pos.pool, pos.closureId, value, bgtValue);
    }

    /// @notice Borrow tokens against a collateralized position.
    function borrow(uint256 positionId, address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        LoanPosition storage pos = positions[positionId];
        _requireOwnerOrLooper(pos.borrower);

        _accrueInterest(token);

        LendingPool storage pool = lendingPools[token];
        uint256 available = pool.totalDeposited > pool.totalBorrowed
            ? pool.totalDeposited - pool.totalBorrowed
            : 0;
        if (available < amount) revert InsufficientLiquidity();

        _settlePositionBorrow(positionId, token);

        tokenBorrows[positionId][token] += amount;
        borrowIndex[positionId][token] = pool.borrowIndexX128;
        pool.totalBorrowed += amount;

        // Check LTV AFTER the borrow
        _requireHealthy(positionId, MAX_LTV);

        // Transfer AFTER state update (CEI pattern)
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Borrowed(positionId, token, amount);
    }

    /// @notice Repay borrowed tokens.
    /// @param amount Use type(uint256).max to repay all.
    function repay(uint256 positionId, address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower == address(0)) revert PositionNotFound();

        _accrueInterest(token);
        _settlePositionBorrow(positionId, token);

        uint256 owed = tokenBorrows[positionId][token];
        uint256 repayAmount = amount > owed ? owed : amount;

        // Transfer tokens first (interactions before final state? No — CEI: check, effects, interactions)
        // Actually we need the tokens first for proper accounting
        IERC20(token).safeTransferFrom(msg.sender, address(this), repayAmount);

        tokenBorrows[positionId][token] -= repayAmount;
        borrowIndex[positionId][token] = lendingPools[token].borrowIndexX128;
        lendingPools[token].totalBorrowed -= repayAmount;

        emit Repaid(positionId, token, repayAmount);
    }

    /// @notice Withdraw value from a collateralized position.
    /// @dev Sends value to msg.sender. Authorized loopers can call on behalf of users.
    function withdrawCollateral(uint256 positionId, uint256 value, uint256 bgtValue) external nonReentrant {
        LoanPosition storage pos = positions[positionId];
        _requireOwnerOrLooper(pos.borrower);
        if (value == 0 && bgtValue == 0) revert ZeroAmount();

        pos.depositedValue -= value;
        pos.depositedBgtValue -= bgtValue;

        // Transfer value from proxy to caller (owner or authorized looper)
        PositionProxy(pos.proxy).execute(
            pos.pool,
            abi.encodeCall(ValueTokenFacet.transfer, (msg.sender, pos.closureId, value, bgtValue))
        );

        // ALWAYS check health after withdrawal, even if depositedValue is 0
        // If value is 0 and debt exists, this will revert (which is correct)
        uint256 debtUSD = _borrowValueUSD(positionId);
        if (debtUSD > 0) {
            uint256 adjColUSD = _adjustedCollateralValueUSD(positionId);
            if (debtUSD * PRECISION > adjColUSD * MAX_LTV) revert ExceedsMaxLTV();
        }

        emit CollateralWithdrawn(positionId, value, bgtValue);
    }

    // ============================================================
    //                     LENDER (LP) FUNCTIONS
    // ============================================================

    /// @notice Deposit tokens into a lending pool to earn interest.
    function depositLiquidity(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _accrueInterest(token);

        LendingPool storage pool = lendingPools[token];

        uint256 shares;
        if (pool.totalShares == 0) {
            shares = amount;
        } else {
            shares = FullMath.mulDiv(amount, pool.totalShares, pool.totalDeposited);
        }

        // Transfer before updating state to get actual received amount
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        pool.totalDeposited += amount;
        pool.totalShares += shares;
        lpShares[token][msg.sender] += shares;

        emit LiquidityDeposited(token, msg.sender, amount, shares);
    }

    /// @notice Withdraw tokens from a lending pool.
    function withdrawLiquidity(address token, uint256 shares) external nonReentrant {
        if (shares == 0) revert ZeroAmount();
        if (lpShares[token][msg.sender] < shares) revert InsufficientShares();

        _accrueInterest(token);

        LendingPool storage pool = lendingPools[token];

        uint256 amount = FullMath.mulDiv(shares, pool.totalDeposited, pool.totalShares);
        uint256 available = pool.totalDeposited > pool.totalBorrowed
            ? pool.totalDeposited - pool.totalBorrowed
            : 0;
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
    /// @dev The liquidator repays debt and receives proportional collateral value + bonus.
    ///      The liquidator gets a Burve value position transferred to them (they handle
    ///      redemption themselves). This avoids complex swap logic inside the contract.
    /// @param positionId The position to liquidate.
    /// @param debtToken The token to repay.
    /// @param repayAmount The amount of debt to repay (partial liquidation allowed).
    function liquidate(
        uint256 positionId,
        address debtToken,
        uint256 repayAmount
    ) external nonReentrant {
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower == address(0)) revert PositionNotFound();

        // Accrue interest on the debt token
        _accrueInterest(debtToken);
        _settlePositionBorrow(positionId, debtToken);

        // Check that position is unhealthy
        uint256 adjColUSD = _adjustedCollateralValueUSD(positionId);
        uint256 debtUSD = _borrowValueUSD(positionId);
        if (debtUSD * PRECISION <= adjColUSD * LIQUIDATION_LTV) revert PositionHealthy();

        // Validate repay amount
        uint256 owed = tokenBorrows[positionId][debtToken];
        if (repayAmount > owed) revert ExcessRepayment();

        // Step 1: Liquidator transfers debt tokens to this contract
        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), repayAmount);

        // Step 2: Update debt accounting
        tokenBorrows[positionId][debtToken] -= repayAmount;
        borrowIndex[positionId][debtToken] = lendingPools[debtToken].borrowIndexX128;
        lendingPools[debtToken].totalBorrowed -= repayAmount;

        // Step 3: Calculate value to seize
        // repaidUSD = repayAmount in USD terms
        uint8 decimals = tokenDecimals[debtToken];
        address feed = priceFeeds[debtToken];
        if (feed == address(0)) revert NoPriceFeed();
        uint256 repaidUSD = PositionValuer.valueTokenUSD(repayAmount, decimals, feed);

        // Seize collateral worth repaidUSD * (1 + LIQUIDATION_BONUS) in value units
        uint256 seizeUSD = FullMath.mulDiv(repaidUSD, PRECISION + LIQUIDATION_BONUS, PRECISION);
        uint256 rawColUSD = _collateralValueUSD(pos.pool, pos.closureId, pos.depositedValue, pos.depositedBgtValue);

        // Calculate proportional value to seize (cap at total deposited)
        uint256 seizeValue;
        if (seizeUSD >= rawColUSD || rawColUSD == 0) {
            // Full liquidation
            seizeValue = pos.depositedValue;
        } else {
            seizeValue = FullMath.mulDiv(pos.depositedValue, seizeUSD, rawColUSD);
        }

        // Cap seizeValue at depositedValue
        if (seizeValue > pos.depositedValue) seizeValue = pos.depositedValue;

        // Step 4: Transfer seized value position from proxy to liquidator
        pos.depositedValue -= seizeValue;
        PositionProxy(pos.proxy).execute(
            pos.pool,
            abi.encodeCall(ValueTokenFacet.transfer, (msg.sender, pos.closureId, seizeValue, 0))
        );

        emit Liquidated(positionId, msg.sender, debtToken, repayAmount, seizeValue);
    }

    // ============================================================
    //                     FEE PASS-THROUGH
    // ============================================================

    /// @notice Collect Burve trading fee earnings from a position and send to recipient.
    function collectPositionEarnings(uint256 positionId, address recipient) external nonReentrant {
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower != msg.sender) revert NotPositionOwner();

        PositionProxy(pos.proxy).execute(
            pos.pool,
            abi.encodeCall(IBurveMultiValue.collectEarnings, (pos.proxy, pos.closureId))
        );

        // Transfer collected tokens from proxy using the cached token list
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

    /// @notice Health factor: (adjustedCollateralUSD * LIQUIDATION_LTV) / debtUSD.
    ///         Returns type(uint256).max if no debt.
    function healthFactor(uint256 positionId) external view returns (uint256) {
        uint256 debtUSD = _borrowValueUSD(positionId);
        if (debtUSD == 0) return type(uint256).max;
        uint256 adjColUSD = _adjustedCollateralValueUSD(positionId);
        return FullMath.mulDiv(adjColUSD, LIQUIDATION_LTV, debtUSD);
    }

    function collateralValueUSD(uint256 positionId) public view returns (uint256) {
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower == address(0)) return 0;
        return _collateralValueUSD(pos.pool, pos.closureId, pos.depositedValue, pos.depositedBgtValue);
    }

    function borrowValueUSD(uint256 positionId) public view returns (uint256) {
        return _borrowValueUSD(positionId);
    }

    function adjustedCollateralValueUSD(uint256 positionId) public view returns (uint256) {
        return _adjustedCollateralValueUSD(positionId);
    }

    function maxBorrowable(uint256 positionId, address token) external view returns (uint256 maxAmount) {
        uint256 adjColUSD = _adjustedCollateralValueUSD(positionId);
        uint256 debtUSD = _borrowValueUSD(positionId);

        uint256 maxDebtUSD = FullMath.mulDiv(adjColUSD, MAX_LTV, PRECISION);
        if (debtUSD >= maxDebtUSD) return 0;
        uint256 remainingUSD = maxDebtUSD - debtUSD;

        address feed = priceFeeds[token];
        if (feed == address(0)) return 0;
        uint8 decimals = tokenDecimals[token];
        maxAmount = PositionValuer.usdToTokenAmount(remainingUSD, decimals, feed);

        LendingPool storage pool = lendingPools[token];
        uint256 available = pool.totalDeposited > pool.totalBorrowed
            ? pool.totalDeposited - pool.totalBorrowed
            : 0;
        if (maxAmount > available) maxAmount = available;
    }

    function currentBorrow(uint256 positionId, address token) external view returns (uint256) {
        return _currentBorrow(positionId, token);
    }

    function getProxyAddress(uint256 positionId) external view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(positionId));
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(type(PositionProxy).creationCode))
        )))));
    }

    // ============================================================
    //                     INTERNAL FUNCTIONS
    // ============================================================

    function _requireOwnerOrLooper(address borrower) internal view {
        if (msg.sender != borrower && !authorizedLoopers[msg.sender]) revert NotPositionOwner();
    }

    function _requireHealthy(uint256 positionId, uint256 maxLtv) internal view {
        uint256 adjColUSD = _adjustedCollateralValueUSD(positionId);
        uint256 debtUSD = _borrowValueUSD(positionId);
        if (debtUSD * PRECISION > adjColUSD * maxLtv) revert ExceedsMaxLTV();
    }

    function _deployProxy(uint256 positionId) internal returns (address proxy) {
        bytes32 salt = keccak256(abi.encodePacked(positionId));
        proxy = address(new PositionProxy{salt: salt}());
    }

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

        uint256 borrowMultiplier = InterestRateModel.getBorrowMultiplierX128(
            pool.totalBorrowed, pool.totalDeposited, timeDelta
        );
        pool.borrowIndexX128 = FullMath.mulDiv(pool.borrowIndexX128, borrowMultiplier, X128);

        uint256 interestEarned = FullMath.mulDiv(pool.totalBorrowed, borrowMultiplier - X128, X128);
        uint256 reserveCut = FullMath.mulDiv(interestEarned, InterestRateModel.RESERVE_FACTOR, PRECISION);
        pool.totalBorrowed += interestEarned;
        pool.totalDeposited += interestEarned - reserveCut;

        if (pool.totalShares > 0 && pool.totalDeposited > 0) {
            uint256 supplyMultiplier = InterestRateModel.getSupplyMultiplierX128(
                pool.totalBorrowed - interestEarned,
                pool.totalDeposited - (interestEarned - reserveCut),
                timeDelta
            );
            pool.supplyIndexX128 = FullMath.mulDiv(pool.supplyIndexX128, supplyMultiplier, X128);
        }

        pool.lastAccrualTimestamp = block.timestamp;
    }

    function _settlePositionBorrow(uint256 positionId, address token) internal {
        uint256 principal = tokenBorrows[positionId][token];
        if (principal == 0) return;

        uint256 oldIndex = borrowIndex[positionId][token];
        uint256 currentIndex = lendingPools[token].borrowIndexX128;

        if (oldIndex == 0 || oldIndex == currentIndex) return;

        uint256 newPrincipal = FullMath.mulDiv(principal, currentIndex, oldIndex);
        tokenBorrows[positionId][token] = newPrincipal;
        borrowIndex[positionId][token] = currentIndex;
    }

    function _currentBorrow(uint256 positionId, address token) internal view returns (uint256) {
        uint256 principal = tokenBorrows[positionId][token];
        if (principal == 0) return 0;

        uint256 oldIndex = borrowIndex[positionId][token];
        uint256 currentIndex = lendingPools[token].borrowIndexX128;
        if (oldIndex == 0 || currentIndex == 0) return principal;

        LendingPool storage pool = lendingPools[token];
        uint256 timeDelta = block.timestamp - pool.lastAccrualTimestamp;
        if (timeDelta > 0) {
            uint256 multiplier = InterestRateModel.getBorrowMultiplierX128(
                pool.totalBorrowed, pool.totalDeposited, timeDelta
            );
            currentIndex = FullMath.mulDiv(currentIndex, multiplier, X128);
        }

        return FullMath.mulDiv(principal, currentIndex, oldIndex);
    }

    function _collateralValueUSD(
        address pool,
        uint16 closureId,
        uint256 value,
        uint256 bgtValue
    ) internal view returns (uint256) {
        return PositionValuer.valuePositionUSD(pool, closureId, value, bgtValue, priceFeeds);
    }

    function _adjustedCollateralValueUSD(uint256 positionId) internal view returns (uint256) {
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower == address(0)) return 0;
        return PositionValuer.weightedValuePositionUSD(
            pos.pool, pos.closureId, pos.depositedValue, pos.depositedBgtValue,
            priceFeeds, collateralFactors
        );
    }

    function _borrowValueUSD(uint256 positionId) internal view returns (uint256 totalUSD) {
        LoanPosition storage pos = positions[positionId];
        if (pos.borrower == address(0)) return 0;

        address[] memory poolTokens = IBurveMultiSimplex(pos.pool).getTokens();
        for (uint256 i = 0; i < poolTokens.length; i++) {
            address token = poolTokens[i];
            uint256 owed = _currentBorrow(positionId, token);
            if (owed == 0) continue;

            uint8 decimals = tokenDecimals[token];
            address feed = priceFeeds[token];
            if (feed == address(0)) revert NoPriceFeed();
            totalUSD += PositionValuer.valueTokenUSD(owed, decimals, feed);
        }
    }
}
