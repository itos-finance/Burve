// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ClosureId} from "./Closure.sol";
import {LiqFacet} from "./facets/LiqFacet.sol";
import {SimplexFacet} from "./facets/SimplexFacet.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {TransferHelper} from "../TransferHelper.sol";

/// A token contract we use to wrap the BurveMulti swap contract so that we can issue
/// an ERC20 for each CID people LP into. It effectively just takes ownership of liquidity
/// and accounts who owns what.
contract BurveMultiLPToken is ERC20 {
    LiqFacet public burveMulti;
    ClosureId public cid; // Which cid this governs
    address public depositToken; // Which token we're depositing. Can be freely changed.

    constructor(
        ClosureId _cid,
        address _burveMulti
    ) ERC20(getName(_cid, _burveMulti), getSymbol(_cid, _burveMulti)) {
        cid = _cid;
        burveMulti = LiqFacet(_burveMulti);
    }

    /// Tell us beforehand which token you want to deposit.
    /// Use a multicall contract to set this and then mint. We'll transferFrom
    /// this token and mint with it, so even if you mess this up, or someone changes
    /// this from under you because you didn't do it in a multicall, you won't even
    /// transfer the tokens unless you gave an approval for some reason. And even then you'll
    /// just end up with LP tokens.
    function setDepositToken(address newDepositToken) external {
        // Anyone can set this.
        depositToken = newDepositToken;
    }

    /// Mints the tokens for shares in the underlying burve multi pool.
    /// The liquidity is indirectly owned by this contract.
    /// @param value The amount of the deposit token you want to deposit.
    function mint(address recipient, uint256 value) external {
        TrasnferHelper.safeTransferFrom(
            depositToken,
            _msgSender(),
            address(this),
            value
        );
        ERC20(depositToken).approve(address(burveMulti), value);
        uint256 shares = burveMulti.addLiq(
            address(this),
            ClosureId.unwrap(_cid),
            depositToken,
            value
        );
        _mint(recipient, shares);
    }

    /// Burns the given amount of LP tokens and get back its respective amount
    /// of tokens it was LPing with.
    /// @param account The account whos shares we're burning.
    /// We give the underlying tokens to the msg.sender, since can own your tokens anyways.
    /// @param shares The number of shares/LP tokens to remove.
    function burn(address account, uint256 shares) external {
        _spendAllowance(account, _msgSender(), shares);
        burveMulti.removeLiq(_msgSender(), cid, shares);
        _burn(account, shares);
    }

    function getName(
        ClosureId _cid,
        address _burveMulti
    ) private view returns (string memory name) {
        string calldata poolName = SimplexFacet(_burveMulti).getName();
        string memory num = Strings.toString(ClosureId.unwrap(_cid));
        name = string.concat("BurveMulti", poolName, "-", num);
    }

    function getSymbol(
        ClosureId _cid,
        address _burveMulti
    ) private view returns (string memory name) {
        string calldata poolName = SimplexFacet(_burveMulti).getName();
        string memory num = Strings.toString(ClosureId.unwrap(_cid));
        name = string.concat(poolName, "-", num);
    }
}
