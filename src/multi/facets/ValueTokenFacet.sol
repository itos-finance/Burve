// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Store} from "../Store.sol";
import {Asset} from "../Asset.sol";
import {ClosureId} from "../closure/Id.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";

struct ValueAllowances {
    mapping(uint16 => mapping(address => mapping(address => uint256))) _allowances;
    mapping(uint16 => mapping(address => mapping(address => uint256))) _bgtAllowances;
}

/// An ERC20 interface for the Value token which is mint and burned by unstaking/staking value.
contract ValueTokenFacet is ReentrancyGuardTransient {
    /// Thrown when trying to spend more value than allowed by the owner.
    error InsufficientValueAllowance(
        address owner,
        address spender,
        uint16 _cid,
        uint256 valueAllowance,
        uint256 value
    );
    /// Thrown when trying to spend more bgt value than allowed by the owner.
    error InsufficientBgtValueAllowance(
        address owner,
        address spender,
        uint16 _cid,
        uint256 bgtValueAllowance,
        uint256 bgtValue
    );

    function balanceOf(
        address account,
        uint16 _cid
    ) public view returns (uint256 value, uint256 bgtValue) {
        ClosureId cid = ClosureId.wrap(_cid);
        Asset storage a = Store.assets().assets[account][cid];
        value = a.value;
        bgtValue = a.bgtValue;
    }

    function transfer(
        address receipient,
        uint16 _cid,
        uint256 value,
        uint256 bgtValue
    ) external nonReentrant returns (bool) {
        ClosureId cid = ClosureId.wrap(_cid);
        Store.closure(cid).trimAllBalances();
        Store.assets().remove(msg.sender, cid, value, bgtValue);
        Store.assets().add(receipient, cid, value, bgtValue);
        return true;
    }

    function allowance(
        address owner,
        address spender,
        uint16 _cid
    ) public view returns (uint256 valueAllowance, uint256 bgtAllowance) {
        ValueAllowances storage allowances = Store.valueAllowances();
        valueAllowance = allowances._allowances[_cid][owner][spender];
        bgtAllowance = allowances._bgtAllowances[_cid][owner][spender];
    }

    function approve(
        address spender,
        uint16 _cid,
        uint256 value,
        uint256 bgtValue
    ) public returns (bool) {
        ValueAllowances storage allowances = Store.valueAllowances();
        allowances._allowances[_cid][msg.sender][spender] = value;
        allowances._bgtAllowances[_cid][msg.sender][spender] = bgtValue;
        return true;
    }

    function transferFrom(
        address owner,
        address recipient,
        uint16 _cid,
        uint256 value,
        uint256 bgtValue
    ) public nonReentrant returns (bool) {
        address spender = msg.sender;
        ValueAllowances storage allowances = Store.valueAllowances();
        {
            // Deduct value allowance.
            uint256 valueAllowance = allowances._allowances[_cid][owner][
                spender
            ];
            if (valueAllowance < value) {
                revert InsufficientValueAllowance(
                    owner,
                    spender,
                    _cid,
                    valueAllowance,
                    value
                );
            } else if (valueAllowance < type(uint256).max) {
                allowances._allowances[_cid][owner][spender] -= value;
            }
        }
        {
            uint256 bgtAllowance = allowances._bgtAllowances[_cid][owner][
                spender
            ];
            if (bgtAllowance < bgtValue) {
                revert InsufficientBgtValueAllowance(
                    owner,
                    spender,
                    _cid,
                    bgtAllowance,
                    bgtValue
                );
            } else if (bgtAllowance < type(uint256).max) {
                allowances._bgtAllowances[_cid][owner][spender] -= bgtValue;
            }
        }
        ClosureId cid = ClosureId.wrap(_cid);
        Store.closure(cid).trimAllBalances();
        Store.assets().remove(owner, cid, value, bgtValue);
        Store.assets().add(recipient, cid, value, bgtValue);
        return true;
    }

    /* If we include more ERC20 features in the future. */
    /*
    function name() public view override returns (string memory) {
        string memory _name = Store.simplex().name;
        return string.concat("brv", _name);
    }

    function symbol() public view override returns (string memory) {
        string memory _symbol = Store.simplex().symbol;
        return string.concat("brv", _symbol);
    }
    */
}
