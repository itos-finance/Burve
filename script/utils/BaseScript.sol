// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {MockERC4626} from "../../test/mocks/MockERC4626.sol";
import {SimplexDiamond as BurveDiamond} from "../../src/multi/Diamond.sol";
import {ValueFacet} from "../../src/multi/facets/ValueFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {LockFacet} from "../../src/multi/facets/LockFacet.sol";
import {VaultFacet} from "../../src/multi/facets/VaultFacet.sol";
import {ValueTokenFacet} from "../../src/multi/facets/ValueTokenFacet.sol";

abstract contract BaseScript is Script {
    // Core contracts
    BurveDiamond public diamond;
    ValueFacet public valueFacet;
    SwapFacet public swapFacet;
    SimplexFacet public simplexFacet;
    LockFacet public lockFacet;
    VaultFacet public vaultFacet;
    ValueTokenFacet public valueTokenFacet;

    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockERC20 public dai;
    MockERC20 public weth;

    // Mock vaults
    MockERC4626 public usdcVault;
    MockERC4626 public usdtVault;
    MockERC4626 public daiVault;
    MockERC4626 public wethVault;

    function setUp() public virtual {
        // Load deployed addresses from environment
        address diamondAddr = vm.envAddress("DIAMOND_ADDRESS");
        diamond = BurveDiamond(payable(diamondAddr));
        valueFacet = ValueFacet(diamondAddr);
        swapFacet = SwapFacet(diamondAddr);
        simplexFacet = SimplexFacet(diamondAddr);
        lockFacet = LockFacet(diamondAddr);
        vaultFacet = VaultFacet(diamondAddr);
        valueTokenFacet = ValueTokenFacet(diamondAddr);

        // Mock tokens
        usdc = MockERC20(vm.envAddress("USDC_ADDRESS"));
        usdt = MockERC20(vm.envAddress("USDT_ADDRESS"));
        dai = MockERC20(vm.envAddress("DAI_ADDRESS"));
        weth = MockERC20(vm.envAddress("WETH_ADDRESS"));

        // Mock vaults
        usdcVault = MockERC4626(vm.envAddress("USDC_VAULT_ADDRESS"));
        usdtVault = MockERC4626(vm.envAddress("USDT_VAULT_ADDRESS"));
        daiVault = MockERC4626(vm.envAddress("DAI_VAULT_ADDRESS"));
        wethVault = MockERC4626(vm.envAddress("WETH_VAULT_ADDRESS"));
    }

    // Helper function to get the appropriate private key
    function _getPrivateKey() internal view returns (uint256) {
        return vm.envUint("PRIVATE_KEY");
    }

    // Helper function to get the appropriate sender address
    function _getSender() internal view returns (address) {
        return vm.addr(_getPrivateKey());
    }

    // Helper function to mint tokens and approve spending
    function _mintAndApprove(
        address token,
        address to,
        uint256 amount
    ) internal {
        MockERC20(token).mint(to, amount);
        MockERC20(token).approve(address(diamond), amount);
    }

    // Helper to get token address by index
    function _getTokenByIndex(uint8 index) internal view returns (address) {
        if (index == 0) return address(usdc);
        if (index == 1) return address(usdt);
        if (index == 2) return address(dai);
        if (index == 3) return address(weth);
        revert("Invalid token index");
    }

    // Helper to get vault address by index
    function _getVaultByIndex(uint8 index) internal view returns (address) {
        if (index == 0) return address(usdcVault);
        if (index == 1) return address(usdtVault);
        if (index == 2) return address(daiVault);
        if (index == 3) return address(wethVault);
        revert("Invalid vault index");
    }
}
