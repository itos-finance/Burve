// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {E4626ViewAdjustor} from "../../../src/integrations/adjustor/E4626ViewAdjustor.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockERC4626} from "../../mocks/MockERC4626.sol";

contract E4626ViewAdjustorTest is Test {
    E4626ViewAdjustor public adj;
    // asset and vault used with adjustor
    address asset;
    address vault;
    // asset and vault unrelated to adjustor
    address mysteryAsset;
    address mysteryVault;

    function setUp() public {
        ERC20 eth = new MockERC20("Ether", "ETH", 18);
        asset = address(eth);
        vault = address(
            new MockERC4626(eth, "Liquid staked Ether 2.0", "stETH")
        );
        MockERC20(asset).mint(address(this), 100e18);
        MockERC20(asset).approve(vault, type(uint256).max);
        // Deposit and mint to the vault so the ratio is not an even number.
        MockERC4626(vault).deposit(10e18, address(this));
        MockERC20(asset).mint(address(vault), 37e18);

        ERC20 mystery = new MockERC20("unknown", "?", 18);
        mysteryAsset = address(mystery);
        mysteryVault = address(new MockERC4626(mystery, "Other vault", "oV"));

        adj = new E4626ViewAdjustor(asset);
    }

    // constructor tests

    function testConstructor() public view {
        assertEq(adj.assetToken(), asset);
    }

    // toNominal uint tests

    function testToNominalUint() public view {
        uint256 real = 10e18;
        uint256 nom = adj.toNominal(vault, real, true);
        assertEq(nom, IERC4626(vault).convertToAssets(real));
    }

    function testToNominalUintCallsConvertToAssets() public {
        uint256 real = 10e18;
        vm.expectCall(
            vault,
            abi.encodeCall(IERC4626(vault).convertToAssets, (real))
        );
        adj.toNominal(vault, real, true);
    }

    function testRevertToNominalUintAssetMismatch() public {
        uint256 real = 10e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                E4626ViewAdjustor.AssetMismatch.selector,
                mysteryAsset,
                asset
            )
        );
        adj.toNominal(mysteryVault, real, true);
    }

    // toNominal int tests

    function testToNominalIntPositive() public view {
        int256 real = 10e18;
        int256 nom = adj.toNominal(vault, real, true);
        assertEq(nom, int256(IERC4626(vault).convertToAssets(uint256(real))));
    }

    function testToNominalIntNegative() public view {
        int256 real = -10e18;
        int256 nom = adj.toNominal(vault, real, true);
        assertEq(nom, -int256(IERC4626(vault).convertToAssets(uint256(-real))));
    }

    function testToNominalIntPositiveCallsConvertToAssets() public {
        int256 real = 10e18;
        vm.expectCall(
            vault,
            abi.encodeCall(IERC4626(vault).convertToAssets, (uint256(real)))
        );
        adj.toNominal(vault, real, true);
    }

    function testToNominalIntNegativeCallsConvertToAssets() public {
        int256 real = -10e18;
        vm.expectCall(
            vault,
            abi.encodeCall(IERC4626(vault).convertToAssets, (uint256(-real)))
        );
        adj.toNominal(vault, real, true);
    }

    function testRevertToNominalIntAssetMismatch() public {
        int256 real = 10e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                E4626ViewAdjustor.AssetMismatch.selector,
                mysteryAsset,
                asset
            )
        );
        adj.toNominal(mysteryVault, real, true);
    }

    // toReal uint tests

    function testToRealUint() public view {
        uint256 nom = 10e18;
        uint256 real = adj.toReal(vault, nom, true);
        assertEq(real, IERC4626(vault).convertToShares(nom));
    }

    function testToRealUintCallsConvertToShares() public {
        uint256 nom = 10e18;
        vm.expectCall(
            vault,
            abi.encodeCall(IERC4626(vault).convertToShares, (nom))
        );
        adj.toReal(vault, nom, true);
    }

    function testRevertToRealUintAssetMismatch() public {
        uint256 nom = 10e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                E4626ViewAdjustor.AssetMismatch.selector,
                mysteryAsset,
                asset
            )
        );
        adj.toReal(mysteryVault, nom, true);
    }

    // toReal int tests

    function testToRealIntPositive() public view {
        int256 nom = 10e18;
        int256 real = adj.toReal(vault, nom, true);
        assertEq(real, int256(IERC4626(vault).convertToShares(uint256(nom))));
    }

    function testToRealIntNegative() public view {
        int256 nom = -10e18;
        int256 real = adj.toReal(vault, nom, true);
        assertEq(real, -int256(IERC4626(vault).convertToShares(uint256(-nom))));
    }

    function testToRealIntPositiveCallsConvertToShares() public {
        int256 nom = 10e18;
        vm.expectCall(
            vault,
            abi.encodeCall(IERC4626(vault).convertToShares, (uint256(nom)))
        );
        adj.toReal(vault, nom, true);
    }

    function testToRealIntNegativeCallsConvertToShares() public {
        int256 nom = -10e18;
        vm.expectCall(
            vault,
            abi.encodeCall(IERC4626(vault).convertToShares, (uint256(-nom)))
        );
        adj.toReal(vault, nom, true);
    }

    function testRevertToRealIntAssetMismatch() public {
        int256 nom = 10e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                E4626ViewAdjustor.AssetMismatch.selector,
                mysteryAsset,
                asset
            )
        );
        adj.toReal(mysteryVault, nom, true);
    }
}
