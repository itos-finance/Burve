// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {AdminLib} from "Commons/Util/Admin.sol";

import {FullMath} from "../FullMath.sol";
import {IKodiakIsland} from "./integrations/kodiak/IKodiakIsland.sol";
import {IStationProxy} from "./IStationProxy.sol";
import {IUniswapV3Pool} from "./integrations/kodiak/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "./integrations/uniswap/LiquidityAmounts.sol";
import {TransferHelper} from "../TransferHelper.sol";
import {TickMath} from "./integrations/uniswap/TickMath.sol";
import {TickRange} from "./TickRange.sol";

contract Burve is ERC20 {
    uint256 private constant X96_MASK = (1 << 96) - 1;
    uint256 private constant UNIT_NOMINAL_LIQ_X64 = 1 << 64;

    IUniswapV3Pool public pool;
    IERC20 public token0;
    IERC20 public token1;

    IKodiakIsland public island;
    IStationProxy public stationProxy;

    /// The n ranges.
    TickRange[] public ranges;

    /// The relative liquidity for our n ranges.
    /// If there is an island that distribution lies at index 0.
    uint256[] public distX96;

    /// Total nominal liquidity in Burve.
    uint128 public totalNominalLiq;

    /// Total shares of nominal liquidity in Burve.
    uint256 public totalShares;

    /// Mapping of owner to island shares they own.
    mapping(address owner => uint256 islandShares) public islandSharesPerOwner;

    /// Emitted when shares are minted.
    event Mint(
        address indexed sender,
        address indexed recipient,
        uint256 shares
    );
    /// Emitted when shares are burned.
    event Burn(address indexed owner, uint256 shares);
    /// Emitted when the station proxy is migrated.
    event MigrateStationProxy(
        IStationProxy indexed from,
        IStationProxy indexed to
    );

    /// Thrown if the given tick range does not match the pools tick spacing.
    error InvalidRange(int24 lower, int24 upper);
    /// Thrown when island specific logic is invoked but the contract was not initialized with an island.
    error NoIsland();
    /// Thrown when the provided island points to a pool that does not match the provided pool.
    error MismatchedIslandPool(address island, address pool);
    /// Thrown in the consturctor if the supplied pool address is the zero address.
    error PoolIsZeroAddress();
    /// Thrown when the number of ranges and number of weights do not match.
    error MismatchedRangeWeightLengths(
        uint256 rangeLength,
        uint256 weightLength
    );
    /// If you burn too much liq at once, we can't collect that amount in one call.
    /// Please split up into multiple calls.
    error TooMuchBurnedAtOnce(uint128 liq, uint256 tokens, bool isX);
    /// Thrown during the uniswapV3MintCallback if the msg.sender is not the pool.
    /// Only the uniswap pool has permission to call this.
    error UniswapV3MintCallbackSenderNotPool(address sender);
    /// Thrown if the price of the pool has moved outside the accepted range during mint / burn.
    error SqrtPriceX96OverLimit(
        uint160 sqrtPriceX96,
        uint160 lowerSqrtPriceLimitX96,
        uint160 upperSqrtPriceLimitX96
    );
    /// Thrown if trying to migrate to the same station proxy.
    error MigrateToSameStationProxy();

    /// Modifier used to ensure the price of the pool is within the accepted lower and upper limits. When minting / burning.
    modifier withinSqrtPX96Limits(
        uint160 lowerSqrtPriceLimitX96,
        uint160 upperSqrtPriceLimitX96
    ) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        if (
            sqrtRatioX96 < lowerSqrtPriceLimitX96 ||
            sqrtRatioX96 > upperSqrtPriceLimitX96
        ) {
            revert SqrtPriceX96OverLimit(
                sqrtRatioX96,
                lowerSqrtPriceLimitX96,
                upperSqrtPriceLimitX96
            );
        }

        _;
    }

    /// Thrown if the price of the pool has moved outside the accepted range during mint / burn.
    error SqrtPriceX96OverLimit(uint160 sqrtPriceX96, uint160 lowerSqrtPriceLimitX96, uint160 upperSqrtPriceLimitX96);

    /// Modifier used to ensure the price of the pool is within the accepted lower and upper limits. When minting / burning.
    modifier withinSqrtPX96Limits(uint160 lowerSqrtPriceLimitX96, uint160 upperSqrtPriceLimitX96) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        if (sqrtRatioX96 < lowerSqrtPriceLimitX96 || sqrtRatioX96 > upperSqrtPriceLimitX96) {
            revert SqrtPriceX96OverLimit(sqrtRatioX96, lowerSqrtPriceLimitX96, upperSqrtPriceLimitX96);
        }

        _;
    }

    /// @param _pool The pool we are wrapping
    /// @param _island The optional island we are wrapping
    /// @param _ranges the n ranges
    /// @param _weights n weights defining the relative liquidity for each range.
    constructor(
        address _pool,
        address _island,
        address _stationProxy,
        TickRange[] memory _ranges,
        uint128[] memory _weights
    ) ERC20(nameFromPool(_pool), symbolFromPool(_pool)) {
        AdminLib.initOwner(msg.sender);

        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        island = IKodiakIsland(_island);
        stationProxy = IStationProxy(_stationProxy);

        if (_pool == address(0x0)) {
            revert PoolIsZeroAddress();
        }

        if (_island != address(0x0) && address(island.pool()) != _pool) {
            revert MismatchedIslandPool(_island, _pool);
        }

        if (_ranges.length != _weights.length) {
            revert MismatchedRangeWeightLengths(
                _ranges.length,
                _weights.length
            );
        }

        int24 tickSpacing = pool.tickSpacing();

        // copy ranges to storage
        for (uint256 i = 0; i < _ranges.length; ++i) {
            TickRange memory range = _ranges[i];

            ranges.push(range);

            if (range.isIsland() && address(island) == address(0x0)) {
                revert NoIsland();
            }

            if (
                (range.lower % tickSpacing != 0) ||
                (range.upper % tickSpacing != 0)
            ) {
                revert InvalidRange(range.lower, range.upper);
            }
        }

        // compute total sum of weights
        uint256 sum = 0;
        for (uint256 i = 0; i < _weights.length; ++i) {
            sum += _weights[i];
        }

        // calculate distribution for each weighted position
        for (uint256 i = 0; i < _weights.length; ++i) {
            distX96.push((_weights[i] << 96) / sum);
        }
    }

    /// @notice Allows the owner to migrate to a new station proxy.
    /// @param newStationProxy The new station proxy to migrate to.
    function migrateStationProxy(IStationProxy newStationProxy) external {
        AdminLib.validateOwner();

        if (address(stationProxy) == address(newStationProxy)) {
            revert MigrateToSameStationProxy();
        }

        emit MigrateStationProxy(stationProxy, newStationProxy);

        stationProxy.migrate(newStationProxy);
        stationProxy = newStationProxy;
    }

    /// @notice mints liquidity for the recipient
    /// @param recipient The recipient of the minted liquidity.
    /// @param mintNominalLiq The amount of nominal liquidity to mint.
    /// @param lowerSqrtPriceLimitX96 The lower price limit of the pool.
    /// @param upperSqrtPriceLimitX96 The upper price limit of the pool.
    function mint(
        address recipient,
        uint128 mintNominalLiq,
        uint160 lowerSqrtPriceLimitX96,
        uint160 upperSqrtPriceLimitX96
    ) external {
        // check sqrtP limits
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        if (
            sqrtRatioX96 < lowerSqrtPriceLimitX96 ||
            sqrtRatioX96 > upperSqrtPriceLimitX96
        ) {
            revert SqrtPriceX96OverLimit(
                sqrtRatioX96,
                lowerSqrtPriceLimitX96,
                upperSqrtPriceLimitX96
            );
        }

        // compound v3 ranges
        compoundV3Ranges();

        // mint liquidity for each range
        for (uint256 i = 0; i < distX96.length; ++i) {
            uint128 liqInRange = uint128(
                shift96(uint256(mintNominalLiq) * distX96[i], true)
            );

            if (liqInRange == 0) {
                continue;
            }

            TickRange memory range = ranges[i];
            if (range.isIsland()) {
                mintIsland(recipient, liqInRange);
            } else {
                // mint the V3 ranges
                pool.mint(
                    address(this),
                    range.lower,
                    range.upper,
                    liqInRange,
                    abi.encode(msg.sender)
                );
            }
        }

        // calculate shares to mint
        uint256 shares;
        if (totalShares == 0) {
            shares = mintNominalLiq;
        } else {
            shares = FullMath.mulDiv(
                mintNominalLiq,
                totalShares,
                totalNominalLiq
            );
        }

        // adjust total nominal liquidity
        totalNominalLiq += mintNominalLiq;

        // mint shares
        totalShares += shares;
        _mint(recipient, shares);

        emit Mint(msg.sender, recipient, shares);
    }

    /// @notice Mints to the island.
    /// @param recipient The recipient of the minted liquidity.
    /// @param liq The amount of liquidity to mint.
    function mintIsland(address recipient, uint128 liq) internal {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(
            sqrtRatioX96,
            liq,
            island.lowerTick(),
            island.upperTick()
        );
        (uint256 mint0, uint256 mint1, uint256 mintShares) = island
            .getMintAmounts(amount0, amount1);

        islandSharesPerOwner[recipient] += mintShares;

        // transfer required tokens to this contract
        TransferHelper.safeTransferFrom(
            address(token0),
            msg.sender,
            address(this),
            mint0
        );
        TransferHelper.safeTransferFrom(
            address(token1),
            msg.sender,
            address(this),
            mint1
        );

        // approve transfer to the island
        SafeERC20.forceApprove(token0, address(island), amount0);
        SafeERC20.forceApprove(token1, address(island), amount1);

        island.mint(mintShares, address(this));

        SafeERC20.forceApprove(token0, address(island), 0);
        SafeERC20.forceApprove(token1, address(island), 0);

        // deposit minted shares to the station proxy
        SafeERC20.forceApprove(island, address(stationProxy), mintShares);
        stationProxy.depositLP(address(island), mintShares, recipient);
        SafeERC20.forceApprove(island, address(stationProxy), 0);
    }

    /// @notice Mints to the island.
    /// @param recipient The recipient of the minted liquidity.
    /// @param liq The amount of liquidity to mint.
    function mintIsland(address recipient, uint128 liq) internal {
        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(liq, island.lowerTick(), island.upperTick());
        (uint256 mint0, uint256 mint1, uint256 mintShares) = island.getMintAmounts(amount0, amount1);

        islandSharesPerOwner[recipient] += mintShares;

        // transfer required tokens to this contract
        TransferHelper.safeTransferFrom(
            address(token0),
            msg.sender,
            address(this),
            mint0
        );
        TransferHelper.safeTransferFrom(
            address(token1),
            msg.sender,
            address(this),
            mint1
        );

        // approve transfer to the island
        SafeERC20.forceApprove(token0, address(island), amount0);
        SafeERC20.forceApprove(token1, address(island), amount1);

        island.mint(mintShares, address(this));

        SafeERC20.forceApprove(token0, address(island), 0);
        SafeERC20.forceApprove(token1, address(island), 0);

        // deposit minted shares to the station proxy
        SafeERC20.forceApprove(island, address(stationProxy), mintShares);
        stationProxy.depositLP(address(island), mintShares, recipient);
        SafeERC20.forceApprove(island, address(stationProxy), 0);
    }

    /// @notice burns liquidity for the msg.sender
    /// @param shares The amount of Burve LP token to burn.
    /// @param lowerSqrtPriceLimitX96 The lower price limit of the pool.
    /// @param upperSqrtPriceLimitX96 The upper price limit of the pool.
    function burn(
        uint256 shares,
        uint160 lowerSqrtPriceLimitX96,
        uint160 upperSqrtPriceLimitX96
    ) external {
        // check sqrtP limits
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        if (
            sqrtRatioX96 < lowerSqrtPriceLimitX96 ||
            sqrtRatioX96 > upperSqrtPriceLimitX96
        ) {
            revert SqrtPriceX96OverLimit(
                sqrtRatioX96,
                lowerSqrtPriceLimitX96,
                upperSqrtPriceLimitX96
            );
        }

        // compound v3 ranges
        compoundV3Ranges();

        uint128 burnLiqNominal = uint128(
            FullMath.mulDiv(shares, uint256(totalNominalLiq), totalShares)
        );

        // adjust total nominal liquidity
        totalNominalLiq -= burnLiqNominal;

        uint256 priorBalance0 = token0.balanceOf(address(this));
        uint256 priorBalance1 = token1.balanceOf(address(this));

        // burn liquidity for each range
        for (uint256 i = 0; i < distX96.length; ++i) {
            TickRange memory range = ranges[i];
            if (range.isIsland()) {
                burnIsland(shares);
            } else {
                uint128 liqInRange = uint128(
                    shift96(uint256(burnLiqNominal) * distX96[i], false)
                );
                if (liqInRange > 0) {
                    burnV3(range, liqInRange);
                }
            }
        }

        // burn shares
        totalShares -= shares;
        _burn(msg.sender, shares);

        // transfer collected tokens to msg.sender
        uint256 postBalance0 = token0.balanceOf(address(this));
        uint256 postBalance1 = token1.balanceOf(address(this));
        TransferHelper.safeTransfer(
            address(token0),
            msg.sender,
            postBalance0 - priorBalance0
        );
        TransferHelper.safeTransfer(
            address(token1),
            msg.sender,
            postBalance1 - priorBalance1
        );

        emit Burn(msg.sender, shares);
    }

    /// @notice Burns share of the island on behalf of msg.sender.
    /// @param shares The amount of Burve LP token to burn.
    function burnIsland(uint256 shares) internal {
        // calculate island shares to burn
        uint256 islandBurnShares = FullMath.mulDiv(
            islandSharesPerOwner[msg.sender],
            shares,
            balanceOf(msg.sender)
        );

        if (islandBurnShares == 0) {
            return;
        }

        islandSharesPerOwner[msg.sender] -= islandBurnShares;

        // withdraw burn shares from the station proxy
        stationProxy.withdrawLP(address(island), islandBurnShares, msg.sender);
        island.burn(islandBurnShares, address(this));
    }

    /// @notice Burns liquidity for a v3 range.
    /// @param range The range to burn.
    /// @param liq The amount of liquidity to burn.
    function burnV3(TickRange memory range, uint128 liq) internal {
        (uint256 x, uint256 y) = pool.burn(range.lower, range.upper, liq);

        if (x > type(uint128).max) revert TooMuchBurnedAtOnce(liq, x, true);
        if (y > type(uint128).max) revert TooMuchBurnedAtOnce(liq, y, false);

        pool.collect(
            address(this),
            range.lower,
            range.upper,
            uint128(x),
            uint128(y)
        );
    }

    /// @notice Collect fees and compound them for each v3 range.
    function compoundV3Ranges() internal {
        // collect fees
        collectV3Fees();

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        uint128 compoundedNominalLiq = getCompoundNominalLiqForCollectedAmounts();
        totalNominalLiq += compoundedNominalLiq;

        // calculate liq and mint amounts
        uint256 totalMint0 = 0;
        uint256 totalMint1 = 0;

        TickRange[] memory memRanges = ranges;
        uint128[] memory compoundLiqs = new uint128[](distX96.length);

        for (uint256 i = 0; i < distX96.length; ++i) {
            TickRange memory range = memRanges[i];

            if (range.isIsland()) {
                continue;
            }

            uint128 compoundLiq = uint128(
                shift96(uint256(compoundedNominalLiq) * distX96[i], true)
            );
            compoundLiqs[i] = compoundLiq;

            if (compoundLiq == 0) {
                continue;
            }

            (uint256 mint0, uint256 mint1) = getAmountsForLiquidity(
                sqrtRatioX96,
                compoundLiq,
                range.lower,
                range.upper
            );
            totalMint0 += mint0;
            totalMint1 += mint1;
        }

        // approve mints
        SafeERC20.forceApprove(token0, address(this), totalMint0);
        SafeERC20.forceApprove(token1, address(this), totalMint1);

        // mint to each range
        for (uint256 i = 0; i < distX96.length; ++i) {
            TickRange memory range = memRanges[i];

            if (range.isIsland()) {
                continue;
            }

            uint128 compoundLiq = compoundLiqs[i];
            if (compoundLiq == 0) {
                continue;
            }

            pool.mint(
                address(this),
                range.lower,
                range.upper,
                compoundLiq,
                abi.encode(address(this))
            );
        }

        // reset approvals
        SafeERC20.forceApprove(token0, address(this), 0);
        SafeERC20.forceApprove(token1, address(this), 0);
    }

    /* Callbacks */

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        if (msg.sender != address(pool)) {
            revert UniswapV3MintCallbackSenderNotPool(msg.sender);
        }

        address source = abi.decode(data, (address));
        TransferHelper.safeTransferFrom(
            address(token0),
            source,
            address(pool),
            amount0Owed
        );
        TransferHelper.safeTransferFrom(
            address(token1),
            source,
            address(pool),
            amount1Owed
        );
    }

    /* internal helpers */

    /// @notice Calculates nominal compound liq for the collected token amounts.
    /// @dev Collected amounts are limited to a max of type(uint192).max and
    ///      computed liquidity is limited to a max of type(uint128).max.
    function getCompoundNominalLiqForCollectedAmounts()
        internal
        view
        returns (uint128 mintNominalLiq)
    {
        // collected amounts on the contract from: fees, compounded leftovers, or tokens sent to the contract.
        uint256 collected0 = token0.balanceOf(address(this));
        uint256 collected1 = token1.balanceOf(address(this));

        // If we collect more than 2^196 in fees, the problem is with the token.
        // If it was worth any meaningful value the world economy would be in the contract.
        // In this case we compound the maximum allowed such that the contract can still operate.
        if (collected0 > type(uint192).max) {
            collected0 = uint256(type(uint192).max);
        }
        if (collected1 > type(uint192).max) {
            collected1 = uint256(type(uint192).max);
        }

        // compute liq in collected amounts
        (
            uint256 amount0InUnitLiqX64,
            uint256 amount1InUnitLiqX64
        ) = getCompoundAmountsPerUnitNominalLiqX64();

        uint256 nominalLiq0 = amount0InUnitLiqX64 > 0
            ? (collected0 << 64) / amount0InUnitLiqX64
            : 0;
        uint256 nominalLiq1 = amount1InUnitLiqX64 > 0
            ? (collected1 << 64) / amount1InUnitLiqX64
            : 0;

        uint256 unsafeNominalLiq = nominalLiq0 < nominalLiq1
            ? nominalLiq0
            : nominalLiq1;

        // min calculated liquidity with the max allowed
        mintNominalLiq = unsafeNominalLiq > type(uint128).max
            ? type(uint128).max
            : uint128(unsafeNominalLiq);

        // during mint the liq at each range is rounded up
        // we subtract by the number of ranges to ensure we have enough liq
        mintNominalLiq = mintNominalLiq <= distX96.length
            ? 0
            : mintNominalLiq - uint128(distX96.length);
    }

    /// @notice Calculates token amounts needed for compounding one X64 unit of nominal liquidity in the v3 ranges.
    /// @dev The liquidity distribution at each range is rounded up.
    function getCompoundAmountsPerUnitNominalLiqX64()
        internal
        view
        returns (uint256 amount0InUnitLiqX64, uint256 amount1InUnitLiqX64)
    {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        for (uint256 i = 0; i < distX96.length; ++i) {
            TickRange memory range = ranges[i];

            // skip the island
            if (range.isIsland()) {
                continue;
            }

            // calculate amount of tokens in unit of liquidity X64
            uint128 liqInRangeX64 = uint128(
                shift96(uint256(UNIT_NOMINAL_LIQ_X64) * distX96[i], true)
            );
            (
                uint256 range0InUnitLiqX64,
                uint256 range1InUnitLiqX64
            ) = getAmountsForLiquidity(
                    sqrtRatioX96,
                    liqInRangeX64,
                    range.lower,
                    range.upper
                );
            amount0InUnitLiqX64 += range0InUnitLiqX64;
            amount1InUnitLiqX64 += range1InUnitLiqX64;
        }
    }

    /// @notice Collects all earned fees for each v3 range.
    function collectV3Fees() internal {
        for (uint256 i = 0; i < distX96.length; ++i) {
            TickRange memory range = ranges[i];

            // skip islands
            if (range.isIsland()) {
                continue;
            }

            // collect fees
            pool.collect(
                address(this),
                range.lower,
                range.upper,
                type(uint128).max,
                type(uint128).max
            );
        }
    }

    /// @notice Calculate token amounts in liquidity for the given range.
    /// @dev The amounts are rounded up.
    /// @param sqrtRatioX96 The current sqrt ratio of the pool.
    /// @param liquidity The amount of liquidity.
    /// @param lower The lower tick of the range.
    /// @param upper The upper tick of the range.
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint128 liquidity,
        int24 lower,
        int24 upper
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(lower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(upper);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity,
            true
        );
    }

    function shift96(
        uint256 a,
        bool roundUp
    ) internal pure returns (uint256 b) {
        b = a >> 96;
        if (roundUp && (a & X96_MASK) > 0) b += 1;
    }

    /// @notice Computes the name for the ERC20 token given the pool address.
    /// @param _pool The pool address.
    /// @return name The name of the ERC20 token.
    function nameFromPool(
        address _pool
    ) private view returns (string memory name) {
        address t0 = IUniswapV3Pool(_pool).token0();
        address t1 = IUniswapV3Pool(_pool).token1();
        name = string.concat(
            ERC20(t0).name(),
            "-",
            ERC20(t1).name(),
            "-Stable-KodiakLP"
        );
    }

    /// @notice Computes the symbol for the ERC20 token given the pool address.
    /// @param _pool The pool address.
    /// @return sym The symbol of the ERC20 token.
    function symbolFromPool(
        address _pool
    ) private view returns (string memory sym) {
        address t0 = IUniswapV3Pool(_pool).token0();
        address t1 = IUniswapV3Pool(_pool).token1();
        sym = string.concat(
            ERC20(t0).symbol(),
            "-",
            ERC20(t1).symbol(),
            "-SLP-KDK"
        );
    }
}
