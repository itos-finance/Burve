// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SwapRouter, Route} from "../../../src/integrations/router/SwapRouter.sol";
import {MultiSetupTest} from "../../facets/MultiSetup.u.sol";

contract MockReentrantSwapper {
    SwapRouter public swapRouter;

    constructor(address _swapRouter) {
        swapRouter = SwapRouter(_swapRouter);
    }

    function swap(
        address recipient,
        address inToken,
        address outToken,
        int256 amountSpecified,
        uint256 amountLimit,
        uint16 _cid
    ) external returns (uint256 inAmount, uint256 outAmount) {
        return
            swapRouter.swap(
                address(this),
                recipient,
                inToken,
                outToken,
                int256(amountLimit),
                new Route[](2)
            );
    }
}

contract SwapRouterTest is MultiSetupTest {
    SwapRouter swapRouter;

    function setUp() public {
        vm.startPrank(owner);
        _newDiamond();
        _newTokens(3);
        _initializeClosure(0x7, 100e18);
        _initializeClosure(0x3, 100e18);
        _fundAccount(alice);
        vm.stopPrank();

        swapRouter = new SwapRouter();
        vm.label(address(swapRouter), "SwapRouter");
    }

    function testSwapExactInMultiRoutes() public {
        vm.startPrank(alice);

        uint256 exactIn = 2e18;
        uint256 minOut = 1996370235934664246; // < 2e18

        // Approve transfer
        token0.approve(address(swapRouter), exactIn);

        // Record balances
        uint256 balanceBefore0 = token0.balanceOf(alice);
        uint256 balanceBefore1 = token1.balanceOf(alice);

        // Execute swap
        Route[] memory routes = new Route[](2); // positive for exact in
        routes[0] = Route({amountSpecified: 1e18, cid: 0x7});
        routes[1] = Route({amountSpecified: 1e18, cid: 0x3});

        (uint256 inAmount, uint256 outAmount) = swapRouter.swap(
            diamond,
            alice,
            address(token0),
            address(token1),
            -int256(minOut), // negative to check min out
            routes
        );

        uint256 balanceAfter0 = token0.balanceOf(alice);
        uint256 balanceAfter1 = token1.balanceOf(alice);

        // Check exact in amounts
        assertEq(balanceBefore0 - exactIn, balanceAfter0, "In transfer");
        assertEq(exactIn, inAmount, "Reported in");

        // Check out amounts
        assertGe(outAmount, minOut, "Out transfer");
        assertEq(balanceAfter1 - balanceBefore1, outAmount, "Reported out");

        vm.stopPrank();
    }

    function testSwapExactOutMultiRoutes() public {
        vm.startPrank(alice);

        uint256 maxIn = 2003642987249544626; // > 2e18
        uint256 exactOut = 2e18;

        // Approve transfer
        token0.approve(address(swapRouter), maxIn);

        // Record balances
        uint256 balanceBefore0 = token0.balanceOf(alice);
        uint256 balanceBefore1 = token1.balanceOf(alice);

        // Execute swap
        Route[] memory routes = new Route[](2); // negative for exact out
        routes[0] = Route({amountSpecified: -1e18, cid: 0x7});
        routes[1] = Route({amountSpecified: -1e18, cid: 0x3});

        (uint256 inAmount, uint256 outAmount) = swapRouter.swap(
            diamond,
            alice,
            address(token0),
            address(token1),
            int256(maxIn), // positive to check max in
            routes
        );

        uint256 balanceAfter0 = token0.balanceOf(alice);
        uint256 balanceAfter1 = token1.balanceOf(alice);

        // Check out amounts
        assertEq(balanceAfter1 - balanceBefore1, exactOut, "Out transfer");
        assertEq(exactOut, outAmount, "Reported out");

        // Check exact in amounts
        assertLe(balanceBefore0 - maxIn, balanceAfter0, "In transfer");
        assertEq(balanceBefore0 - balanceAfter0, inAmount, "Reported in");

        vm.stopPrank();
    }

    function testRevertSwapExactInMultiRoutesInsufficientAmountOut() public {
        vm.startPrank(alice);

        // Approve transfer
        token0.approve(address(swapRouter), 2e18);

        // Execute swap
        Route[] memory routes = new Route[](2); // positive for exact in
        routes[0] = Route({amountSpecified: 1e18, cid: 0x7});
        routes[1] = Route({amountSpecified: 1e18, cid: 0x3});

        // Check revert insufficient amount out
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapRouter.InsufficientAmountOut.selector,
                2e18, // acceptable
                1996370235934664246 // actual
            )
        );
        swapRouter.swap(
            diamond,
            alice,
            address(token0),
            address(token1),
            -2e18, // negative to check min out
            routes
        );

        vm.stopPrank();
    }

    function testRevertSwapExactOutMultiRoutesExcessiveAmountIn() public {
        vm.startPrank(alice);

        // Approve transfer
        token0.approve(address(swapRouter), 2003642987249544626);

        // Execute swap
        Route[] memory routes = new Route[](2); // negative for exact out
        routes[0] = Route({amountSpecified: -1e18, cid: 0x7});
        routes[1] = Route({amountSpecified: -1e18, cid: 0x3});

        // Check revert excessive amount in
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapRouter.ExcessiveAmountIn.selector,
                2e18, // acceptable
                2003642987249544626 // actual
            )
        );
        swapRouter.swap(
            diamond,
            alice,
            address(token0),
            address(token1),
            int256(2e18), // positive to check max in
            routes
        );

        vm.stopPrank();
    }

    function testRevertTokenRequestCBUntrustedTokenRequest() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);

        int256[] memory requests = new int256[](2);
        requests[0] = 1e18;
        requests[1] = -1e18;

        // Check revert untrusted msg.sender
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapRouter.UntrustedTokenRequest.selector,
                address(this)
            )
        );
        swapRouter.tokenRequestCB(tokens, requests, "");
    }

    function testRevertTokenRequestTransientStorageNotSet() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);

        int256[] memory requests = new int256[](2);
        requests[0] = 1e18;
        requests[1] = -1e18;

        // Check revert untrusted msg.sender
        vm.startPrank(address(0x0));
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapRouter.UntrustedTokenRequest.selector,
                address(0x0)
            )
        );
        swapRouter.tokenRequestCB(tokens, requests, "");
        vm.stopPrank();
    }

    function testRevertReentrantSwap() public {
        vm.startPrank(alice);

        MockReentrantSwapper reentrantSwapper = new MockReentrantSwapper(
            address(swapRouter)
        );

        // Check revert due to reentrancy
        vm.expectRevert(SwapRouter.ReentrancyAttempt.selector);
        swapRouter.swap(
            address(reentrantSwapper),
            alice,
            address(token0),
            address(token1),
            0,
            new Route[](2)
        );

        vm.stopPrank();
    }
}
