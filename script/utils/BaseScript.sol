// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;
/*
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {MockERC4626} from "../../test/mocks/MockERC4626.sol";
import {SimplexDiamond} from "../../src/multi/Diamond.sol";
import {LiqFacet} from "../../src/multi/facets/LiqFacet.sol";
import {SimplexFacet} from "../../src/multi/facets/SimplexFacet.sol";
import {SwapFacet} from "../../src/multi/facets/SwapFacet.sol";
import {ViewFacet} from "../../src/multi/facets/ViewFacet.sol";
import {EdgeFacet} from "../../src/multi/facets/EdgeFacet.sol";
import {BurveMultiLPToken} from "../../src/multi/LPToken.sol";
import {TokenRegLib} from "../../src/multi/Token.sol";

abstract contract BaseScript is Script {
    // File path for deployed addresses
    string constant ADDRESSES_FILE = "script/anvil.json";

    // Core contracts
    SimplexDiamond public diamond;
    LiqFacet public liqFacet;
    SimplexFacet public simplexFacet;
    SwapFacet public swapFacet;
    ViewFacet public viewFacet;
    EdgeFacet public edgeFacet;

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

    // LP tokens mapping
    mapping(uint16 => BurveMultiLPToken) public lpTokens;

    function setUp() public virtual {
        // Load deployed addresses
        string memory json = vm.readFile(ADDRESSES_FILE);

        // Core contracts
        address diamondAddr = vm.parseJsonAddress(json, "$.diamond");
        diamond = SimplexDiamond(payable(diamondAddr));
        liqFacet = LiqFacet(diamondAddr);
        simplexFacet = SimplexFacet(diamondAddr);
        swapFacet = SwapFacet(diamondAddr);
        viewFacet = ViewFacet(diamondAddr);
        edgeFacet = EdgeFacet(diamondAddr);

        // Mock tokens
        usdc = MockERC20(vm.parseJsonAddress(json, "$.usdc"));
        usdt = MockERC20(vm.parseJsonAddress(json, "$.usdt"));
        dai = MockERC20(vm.parseJsonAddress(json, "$.dai"));
        weth = MockERC20(vm.parseJsonAddress(json, "$.weth"));

        // Mock vaults
        usdcVault = MockERC4626(vm.parseJsonAddress(json, "$.usdcVault"));
        usdtVault = MockERC4626(vm.parseJsonAddress(json, "$.usdtVault"));
        daiVault = MockERC4626(vm.parseJsonAddress(json, "$.daiVault"));
        wethVault = MockERC4626(vm.parseJsonAddress(json, "$.wethVault"));
    }

    // Helper function to get the appropriate private key
    function _getPrivateKey() internal view returns (uint256) {
        try vm.envUint("ANVIL_DEFAULT_KEY") returns (uint256 key) {
            return key;
        } catch {
            // If not set, return the deployer's private key from .env
            return vm.envUint("DEPLOYER_PRIVATE_KEY");
        }
    }

    // Helper function to get the appropriate sender address
    function _getSender() internal view returns (address) {
        try vm.envAddress("ANVIL_DEFAULT_ADDR") returns (address addr) {
            return addr;
        } catch {
            // If not set, return the deployer's public key from .env
            return vm.envAddress("DEPLOYER_PUBLIC_KEY");
        }
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

    // Helper to get LP token for a closure ID
    function _getLPToken(
        uint16 closureId
    ) internal view returns (BurveMultiLPToken) {
        string memory json = vm.readFile(ADDRESSES_FILE);
        string memory path = string.concat(
            "$.lpTokens.",
            vm.toString(closureId)
        );
        address lpAddr = vm.parseJsonAddress(json, path);
        return BurveMultiLPToken(lpAddr);
    }
}
 */
