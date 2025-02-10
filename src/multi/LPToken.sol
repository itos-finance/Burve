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
    /// Thrown when attempting to mint with an irrelevant token.
    error TokenNotRecognized(address);

    LiqFacet public burveMulti;
    ClosureId public cid; // Which cid this governs

    constructor(
        ClosureId _cid,
        address _burveMulti
    ) ERC20(getName(_cid, _burveMulti), getSymbol(_cid, _burveMulti)) {
        cid = _cid;
        burveMulti = LiqFacet(_burveMulti);
    }

    /// Mints liq for this closure using a single token.
    /// @dev The liquidity is indirectly owned by this contract.
    /// @param value The amount of the deposit token you want to deposit.
    function mint(
        address recipient,
        address depositToken,
        uint128 value
    ) external returns (uint256 shares) {
        // Fetch the needed token
        TransferHelper.safeTransferFrom(
            depositToken,
            _msgSender(),
            address(this),
            value
        );
        ERC20(depositToken).approve(address(burveMulti), value);
        // Setup the single token deposit by fetching its token index.
        SimplexFacet simplex = SimplexFacet(address(burveMulti));
        address[] memory tokens = new address[](1);
        tokens[0] = depositToken;
        int8[] memory idxs = simplex.getIndexes(tokens);
        if (idxs[0] < 0) revert TokenNotRecognized(depositToken);
        // Setup the amount array
        uint8 n = simplex.numVertices();
        uint128[] memory amounts = new uint128[](n);
        amounts[uint8(idxs[0])] = value;
        // Mint to ourselves and then give shares to the recipient.
        shares = burveMulti.addLiq(
            address(this),
            ClosureId.unwrap(cid),
            amounts
        );
        _mint(recipient, shares);
    }

    /// Mint by depositing multiple tokens in according to the token list of the protocol
    /// It is structured so that token amounts irrelevant to the closureId are ignored. This has
    /// the convenient benefit that you can mint with equal token amounts for all tokens in your
    /// Closure just by setting the same value to all entries in the array, even if they're not
    /// relevant to your Closure.
    function mint(
        address recipient,
        uint128[] calldata amounts
    ) external returns (uint256 shares) {
        // Mint to ourselves and then give shares to the recipient.
        shares = burveMulti.addLiq(
            address(this),
            ClosureId.unwrap(cid),
            amounts
        );
        _mint(recipient, shares);
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
        burveMulti.removeLiq(_msgSender(), ClosureId.unwrap(cid), shares);
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
}
