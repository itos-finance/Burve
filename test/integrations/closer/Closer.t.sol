// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Closer} from "../../../src/integrations/closer/Closer.sol";
import {MAX_TOKENS} from "../../../src/multi/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

/// @dev Minimal mock ERC20 for testing.
contract MockERC20 is ERC20 {
    uint8 private _dec;
    constructor(string memory name, string memory symbol, uint8 dec_) ERC20(name, symbol) {
        _dec = dec_;
    }
    function decimals() public view override returns (uint8) { return _dec; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @dev Mock pool that returns a configurable token list via getTokens().
contract MockPool {
    address[] public tokenList;

    constructor(address[] memory _tokens) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenList.push(_tokens[i]);
        }
    }

    function getTokens() external view returns (address[] memory) {
        return tokenList;
    }
}

/// @dev Mock router that simulates a swap by transferring a preset output amount
/// from its own balance to a receiver. The receiver is extracted from the calldata
/// (the outputReceiver field encoded in the swap selector call).
contract MockRouter {
    // token -> amount to send on next swap
    mapping(address => uint256) public nextOutputAmount;
    // token -> receiver override (if set)
    mapping(address => address) public nextOutputReceiver;

    function setSwapOutput(address outToken, uint256 amount, address receiver) external {
        nextOutputAmount[outToken] = amount;
        nextOutputReceiver[outToken] = receiver;
    }

    // Accept any call and perform the mock swap
    fallback() external {
        // We iterate over all configured outputs and send them.
        // For simplicity, we don't parse calldata — the test sets up exactly what should happen.
    }

    function executeSwap(address inToken, address outToken, address receiver) external {
        uint256 amount = nextOutputAmount[outToken];
        require(amount > 0, "MockRouter: no output configured");
        // Pull input tokens (simulating the router taking them)
        uint256 inBal = IERC20(inToken).balanceOf(msg.sender);
        if (inBal > 0) {
            IERC20(inToken).transferFrom(msg.sender, address(this), inBal);
        }
        IERC20(outToken).transfer(receiver, amount);
        nextOutputAmount[outToken] = 0;
    }
}

/// @dev A router that always reverts.
contract FailingRouter {
    fallback() external {
        revert("router failure");
    }
}

/// @dev A router that actually performs the swap by pulling inToken and pushing outToken.
/// It decodes a simple custom calldata format: (address inToken, address outToken, address receiver, uint256 outAmount)
contract SwapRouter {
    fallback() external {
        (address inToken, address outToken, address receiver, uint256 outAmount) =
            abi.decode(msg.data[4:], (address, address, address, uint256));
        // Pull all inToken from caller
        uint256 inBal = IERC20(inToken).balanceOf(msg.sender);
        if (inBal > 0) {
            IERC20(inToken).transferFrom(msg.sender, address(this), inBal);
        }
        // Send outToken
        IERC20(outToken).transfer(receiver, outAmount);
    }
}

contract CloserTest is Test {
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;
    SwapRouter swapRouter;
    Closer closer;
    MockPool pool2; // 2-token pool
    MockPool pool3; // 3-token pool

    // Simple swap calldata selector (matches SwapRouter fallback decoding)
    bytes4 constant SWAP_SIG = bytes4(keccak256("swap(address,address,address,uint256)"));

    function setUp() public {
        tokenA = new MockERC20("TokenA", "A", 18);
        tokenB = new MockERC20("TokenB", "B", 6);
        tokenC = new MockERC20("TokenC", "C", 18);

        swapRouter = new SwapRouter();
        closer = new Closer(address(swapRouter));

        // 2-token pool: [tokenA, tokenB]
        address[] memory twoTokens = new address[](2);
        twoTokens[0] = address(tokenA);
        twoTokens[1] = address(tokenB);
        pool2 = new MockPool(twoTokens);

        // 3-token pool: [tokenA, tokenB, tokenC]
        address[] memory threeTokens = new address[](3);
        threeTokens[0] = address(tokenA);
        threeTokens[1] = address(tokenB);
        threeTokens[2] = address(tokenC);
        pool3 = new MockPool(threeTokens);

        // Fund the router with output tokens for swaps
        tokenA.mint(address(swapRouter), 1000e18);
        tokenB.mint(address(swapRouter), 1000e6);
        tokenC.mint(address(swapRouter), 1000e18);
    }

    /// Build swap calldata for the SwapRouter.
    function _buildSwapData(
        address inToken,
        address outToken,
        address receiver,
        uint256 outAmount
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SWAP_SIG, inToken, outToken, receiver, outAmount);
    }

    // ==================== Two-Token Tests ====================

    function testBurn_TwoTokens_SwapBtoA() public {
        // Simulate removeValue sent tokenA and tokenB to the closer
        tokenA.mint(address(closer), 10e18);
        tokenB.mint(address(closer), 5e6);

        // We want everything in tokenA. Swap tokenB -> tokenA.
        // SwapRouter will give us 5e18 tokenA for the tokenB.
        uint256 swapOut = 5e18;

        bytes[MAX_TOKENS] memory txData;
        // index 0 = tokenA (outToken, skip)
        // index 1 = tokenB (swap to tokenA)
        txData[1] = _buildSwapData(address(tokenB), address(tokenA), address(closer), swapOut);

        uint256 balBefore = tokenA.balanceOf(address(this));
        uint256 outAmount = closer.burn(address(pool2), address(tokenA), txData, 0);
        uint256 balAfter = tokenA.balanceOf(address(this));

        // Should receive original 10e18 + 5e18 from swap
        assertEq(outAmount, 15e18);
        assertEq(balAfter - balBefore, 15e18);
        // Closer should have no tokens left
        assertEq(tokenA.balanceOf(address(closer)), 0);
        assertEq(tokenB.balanceOf(address(closer)), 0);
    }

    function testBurn_TwoTokens_SwapAtoB() public {
        // Everything into tokenB
        tokenA.mint(address(closer), 10e18);
        tokenB.mint(address(closer), 5e6);

        uint256 swapOut = 10e6; // swap tokenA -> tokenB yields 10e6

        bytes[MAX_TOKENS] memory txData;
        // index 0 = tokenA (swap to tokenB)
        txData[0] = _buildSwapData(address(tokenA), address(tokenB), address(closer), swapOut);
        // index 1 = tokenB (outToken, skip)

        uint256 outAmount = closer.burn(address(pool2), address(tokenB), txData, 0);
        assertEq(outAmount, 15e6); // 5e6 original + 10e6 from swap
        assertEq(tokenB.balanceOf(address(this)), 15e6);
        assertEq(tokenA.balanceOf(address(closer)), 0);
    }

    // ==================== Three-Token Tests ====================

    function testBurn_ThreeTokens_SwapAllToA() public {
        tokenA.mint(address(closer), 10e18);
        tokenB.mint(address(closer), 5e6);
        tokenC.mint(address(closer), 8e18);

        bytes[MAX_TOKENS] memory txData;
        // Swap tokenB -> tokenA
        txData[1] = _buildSwapData(address(tokenB), address(tokenA), address(closer), 5e18);
        // Swap tokenC -> tokenA
        txData[2] = _buildSwapData(address(tokenC), address(tokenA), address(closer), 8e18);

        uint256 outAmount = closer.burn(address(pool3), address(tokenA), txData, 0);
        assertEq(outAmount, 23e18); // 10 + 5 + 8
        assertEq(tokenA.balanceOf(address(this)), 23e18);
        assertEq(tokenB.balanceOf(address(closer)), 0);
        assertEq(tokenC.balanceOf(address(closer)), 0);
    }

    function testBurn_ThreeTokens_SwapAllToB() public {
        tokenA.mint(address(closer), 10e18);
        tokenB.mint(address(closer), 5e6);
        tokenC.mint(address(closer), 8e18);

        bytes[MAX_TOKENS] memory txData;
        txData[0] = _buildSwapData(address(tokenA), address(tokenB), address(closer), 10e6);
        txData[2] = _buildSwapData(address(tokenC), address(tokenB), address(closer), 8e6);

        uint256 outAmount = closer.burn(address(pool3), address(tokenB), txData, 0);
        assertEq(outAmount, 23e6);
    }

    // ==================== Only OutToken Balance (No Swaps Needed) ====================

    function testBurn_OnlyOutTokenBalance_NoSwaps() public {
        tokenA.mint(address(closer), 42e18);

        bytes[MAX_TOKENS] memory txData; // all empty

        uint256 outAmount = closer.burn(address(pool2), address(tokenA), txData, 0);
        assertEq(outAmount, 42e18);
        assertEq(tokenA.balanceOf(address(this)), 42e18);
    }

    // ==================== Slippage ====================

    function testBurn_SlippageExact() public {
        tokenA.mint(address(closer), 10e18);

        bytes[MAX_TOKENS] memory txData;
        // minOutAmount exactly equal to balance should pass
        uint256 outAmount = closer.burn(address(pool2), address(tokenA), txData, 10e18);
        assertEq(outAmount, 10e18);
    }

    function testBurn_SlippageExceeded() public {
        tokenA.mint(address(closer), 10e18);

        bytes[MAX_TOKENS] memory txData;
        vm.expectRevert(Closer.SlippageExceeded.selector);
        closer.burn(address(pool2), address(tokenA), txData, 10e18 + 1);
    }

    function testBurn_SlippageExceededMax() public {
        tokenA.mint(address(closer), 1e18);

        bytes[MAX_TOKENS] memory txData;
        vm.expectRevert(Closer.SlippageExceeded.selector);
        closer.burn(address(pool2), address(tokenA), txData, type(uint256).max);
    }

    // ==================== Invalid Token ====================

    function testBurn_InvalidToken() public {
        bytes[MAX_TOKENS] memory txData;
        address fakeToken = makeAddr("fakeToken");

        vm.expectRevert(Closer.InvalidToken.selector);
        closer.burn(address(pool2), fakeToken, txData, 0);
    }

    // ==================== Router Failure ====================

    function testBurn_RouterFailure() public {
        FailingRouter failRouter = new FailingRouter();
        Closer failCloser = new Closer(address(failRouter));

        tokenA.mint(address(failCloser), 10e18);
        tokenB.mint(address(failCloser), 5e6);

        bytes[MAX_TOKENS] memory txData;
        // Provide txData for tokenB so the closer attempts a swap
        txData[1] = hex"deadbeef";

        vm.expectRevert(Closer.RouterFailure.selector);
        failCloser.burn(address(pool2), address(tokenA), txData, 0);
    }

    // ==================== Zero Balance Token Skipped ====================

    function testBurn_SkipsZeroBalanceToken() public {
        // Only tokenA has balance, tokenB has zero — should not attempt swap
        tokenA.mint(address(closer), 10e18);
        // tokenB balance at closer is 0

        bytes[MAX_TOKENS] memory txData;
        // Even though txData[1] has data, tokenB balance is 0 so it's skipped
        txData[1] = _buildSwapData(address(tokenB), address(tokenA), address(closer), 0);

        uint256 outAmount = closer.burn(address(pool2), address(tokenA), txData, 0);
        assertEq(outAmount, 10e18);
    }

    // ==================== Empty TxData Skipped ====================

    function testBurn_SkipsEmptyTxData() public {
        tokenA.mint(address(closer), 10e18);
        tokenB.mint(address(closer), 5e6); // This will remain in the closer

        bytes[MAX_TOKENS] memory txData; // all empty — no swaps

        // Only tokenA is transferred out. tokenB stays because no swap was configured.
        uint256 outAmount = closer.burn(address(pool2), address(tokenA), txData, 0);
        assertEq(outAmount, 10e18);
        // tokenB remains in the closer since no swap was requested
        assertEq(tokenB.balanceOf(address(closer)), 5e6);
    }

    // ==================== Multiple Callers ====================

    function testBurn_DifferentCaller() public {
        tokenA.mint(address(closer), 10e18);

        bytes[MAX_TOKENS] memory txData;

        address alice = makeAddr("alice");
        vm.prank(alice);
        uint256 outAmount = closer.burn(address(pool2), address(tokenA), txData, 0);
        assertEq(outAmount, 10e18);
        assertEq(tokenA.balanceOf(alice), 10e18);
        assertEq(tokenA.balanceOf(address(this)), 0);
    }

    // ==================== Consecutive Burns ====================

    function testBurn_ConsecutiveBurns() public {
        // First burn
        tokenA.mint(address(closer), 10e18);
        bytes[MAX_TOKENS] memory txData;

        closer.burn(address(pool2), address(tokenA), txData, 0);
        assertEq(tokenA.balanceOf(address(this)), 10e18);
        assertEq(tokenA.balanceOf(address(closer)), 0);

        // Second burn — closer has no balance, should return 0
        // But minOutAmount=0 so it doesn't revert, just transfers 0
        uint256 outAmount = closer.burn(address(pool2), address(tokenA), txData, 0);
        assertEq(outAmount, 0);
    }

    // ==================== Return Value ====================

    function testBurn_ReturnsCorrectAmount() public {
        tokenA.mint(address(closer), 7e18);
        tokenB.mint(address(closer), 3e6);

        bytes[MAX_TOKENS] memory txData;
        txData[1] = _buildSwapData(address(tokenB), address(tokenA), address(closer), 3e18);

        uint256 outAmount = closer.burn(address(pool2), address(tokenA), txData, 0);
        assertEq(outAmount, 10e18);
    }
}
