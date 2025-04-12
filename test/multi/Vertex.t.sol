// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {VertexId, VertexLib} from "../../src/multi/vertex/Id.sol";
import {Vertex} from "../../src/multi/vertex/Vertex.sol";
import {TokenRegistry} from "../../src/multi/Token.sol";
import {VaultType} from "../../src/multi/vertex/VaultProxy.sol";
import {ClosureId, newClosureId} from "../../src/multi/closure/Id.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Store} from "../../src/multi/Store.sol";

contract VertexIdTest is Test {
    function testExactId() public pure {
        assertEq(VertexId.unwrap(VertexLib.newId(0)), 1 << 8);
        assertEq(VertexId.unwrap(VertexLib.minId()), 1 << 8);
        assertEq(VertexId.unwrap(VertexLib.newId(1)), (1 << 9) + 1);
        assertEq(VertexId.unwrap(VertexLib.newId(2)), (1 << 10) + 2);
    }

    function testInc() public pure {
        assertEq(
            VertexId.unwrap(VertexLib.newId(5).inc()),
            VertexId.unwrap(VertexLib.newId(6))
        );
    }
}

/*

contract VertexTest is Test {
    using VertexImpl for Vertex;
    using TokenRegistryImpl for TokenRegistry;

    // Test state variables
    Vertex internal vertex;
    MockERC20 internal token0;
    MockERC20 internal token1;
    MockERC20 internal token2;
    MockERC4626 internal vault0;
    MockERC4626 internal vault1;
    MockERC4626 internal vault2;
    ClosureId[] internal testClosures;

    // Test constants
    uint256 constant INITIAL_BALANCE = 1000000 ether;
    uint256 constant TEST_AMOUNT = 100 ether;

    function setUp() public {
        // Deploy mock ERC20 token first
        token0 = new MockERC20("Test Token 0", "TES0", 18);
        token1 = new MockERC20("Test Token 1", "TES1", 18);
        token2 = new MockERC20("Test Token 2", "TES2", 18);

        // Deploy a second mock ERC20

        // Deploy mock ERC4626 vault with the token as underlying
        vault0 = new MockERC4626(token0, "Mock Vault 0", "MVLT0");
        vault1 = new MockERC4626(token1, "Mock Vault 1", "MVLT1");
        vault2 = new MockERC4626(token2, "Mock Vault 2", "MVLT2");

        // Register token in the registry
        TokenRegistry storage tokenReg = Store.tokenRegistry();
        tokenReg.register(address(token0));
        tokenReg.register(address(token1));
        tokenReg.register(address(token2));

        // Mint some initial tokens
        token0.mint(address(this), INITIAL_BALANCE);
        token1.mint(address(this), INITIAL_BALANCE);
        token2.mint(address(this), INITIAL_BALANCE);

        // Approve vault to spend tokens
        token0.approve(address(vault0), type(uint256).max);
        token1.approve(address(vault1), type(uint256).max);
        token2.approve(address(vault1), type(uint256).max);

        // Initialize vertex
        vertex.init(address(token0), address(vault0), VaultType.E4626);
        Store.vertex((address(token1))).init(
            address(token1),
            address(vault1),
            VaultType.E4626
        );
        Store.vertex(newVertexId(address(token2))).init(
            address(token2),
            address(vault2),
            VaultType.E4626
        );
    }

    function testInitialization() public {
        // Test basic initialization
        VertexId vid = vertex.vid;
        assertTrue(
            vid.isEq(VertexId.wrap(uint16(1 << 8))),
            "Vertex ID should just be 1 in the hot bit"
        );
    }
}
*/
