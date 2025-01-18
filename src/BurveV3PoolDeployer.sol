// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@v3-core/interfaces/IUniswapV3PoolDeployer.sol";

import "@v3-core/UniswapV3Pool.sol";

contract UniswapV3PoolDeployer is IUniswapV3PoolDeployer {
    /// @notice the fee is overridden in the protocol as a dynamic fee but to keep the uniswap pool lookup setup
    /// we will hardcode the fee and tickSpacing to (1,1)
    uint24 INIT_FEE = 1;
    int24 TICK_SPACING_STUB = 1;

    struct Parameters {
        address factory;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
    }

    /// @inheritdoc IUniswapV3PoolDeployer
    Parameters public override parameters;

    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    /// @dev Burve only allows for the deployment of pools by the Burve core contract, unlike UniswapV3 which
    /// usually allows for any entity to create pools
    /// @param factory The contract address of the Uniswap V3 factory
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @notice these two params are no longer valid
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The spacing between usable ticks
    function deploy(
        address factory,
        address token0,
        address token1,
        uint24,
        int24
    ) internal returns (address pool) {
        parameters = Parameters({
            factory: factory,
            token0: token0,
            token1: token1,
            fee: INIT_FEE,
            tickSpacing: TICK_SPACING_STUB
        });
        pool = address(
            new UniswapV3Pool{
                salt: keccak256(abi.encode(token0, token1, INIT_FEE))
            }()
        );
        delete parameters;
    }
}
