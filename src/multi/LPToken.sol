// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ClosureId} from "./Closure.sol";
import {LiqFacet} from "./facets/LiqFacet.sol";
import {SimplexFacet} from "./facets/SimplexFacet.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {TransferHelper} from "../TransferHelper.sol";

/// A token contract we use to wrap the BurveMulti swap contract so that we can issue
/// an ERC20 for each CID people LP into. It effectively just takes ownership of liquidity
/// and accounts who owns what.
contract BurveMultiLPToken is ERC20 {
    LiqFacet public burveMulti;
    ClosureId public cid; // Which cid this governs
    error NotImplemented(); // generic mint is not implemented for Burve LP tokens.

    constructor(
        ClosureId _cid,
        address _burveMulti
    ) ERC20(getName(_cid, _burveMulti), getSymbol(_cid, _burveMulti)) {
        cid = _cid;
        burveMulti = LiqFacet(_burveMulti);
    }

    /// the burve lp token leave the mint unimplemented. Rather use the
    /// single or multi-token mint below.
    function mint(address, uint256) external pure {
        revert NotImplemented();
    }

    /// Burns the given amount of LP tokens and get back its respective amount
    /// of tokens it was LPing with.
    /// @param account The account whos shares we're burning.
    /// We give the underlying tokens to the msg.sender, since can own your tokens anyways.
    /// @param shares The number of shares/LP tokens to remove.
    function burn(address account, uint256 shares) external {
        if (account != _msgSender()) {
            _spendAllowance(account, _msgSender(), shares);
        }
        // TODO (terence) - Asset is actually owned by the LPToken, switch from msg.sender to address(this)
        burveMulti.removeLiq(address(this), ClosureId.unwrap(cid), shares);
        _burn(account, shares);
    }

    function getName(
        ClosureId _cid,
        address _burveMulti
    ) private view returns (string memory name) {
        string memory poolName = SimplexFacet(_burveMulti).getName();
        string memory num = Strings.toString(ClosureId.unwrap(_cid));
        name = string.concat("BurveMulti", poolName, "-", num);
    }

    function getSymbol(
        ClosureId _cid,
        address _burveMulti
    ) private view returns (string memory name) {
        string memory poolName = SimplexFacet(_burveMulti).getName();
        string memory num = Strings.toString(ClosureId.unwrap(_cid));
        name = string.concat(poolName, "-", num);
    }

    /* Additional mint methods */

    /// Mint liquidity into the CID using just one token.
    /// @dev Most suitable when adding a small amount relative to the pool size.
    function mintWithOneToken(
        address recipient,
        address token,
        uint128 amount
    ) external returns (uint256 shares) {
        TransferHelper.safeTransferFrom(
            token,
            _msgSender(),
            address(this),
            amount
        );
        ERC20(token).approve(address(burveMulti), amount);
        shares = burveMulti.addLiq(
            address(this),
            ClosureId.unwrap(cid),
            token,
            amount
        );
        _mint(recipient, shares);
    }

    /// Mint liquidity into the CID by providing an amount (potentially zero) of each token.
    /// @dev This type of minting avoids slippage.
    function mintWithMultipleTokens(
        address recipient,
        address payer,
        uint128[] memory amounts
    ) external returns (uint256 shares) {
        shares = burveMulti.addLiq(
            recipient,
            payer,
            ClosureId.unwrap(cid),
            amounts
        );
        _mint(recipient, shares);
    }
}
