// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {console2} from "forge-std/console2.sol";
import {RFTPayer, RFTLib} from "Commons/Util/RFT.sol";
import {IAdjustor} from "./adjustor/IAdjustor.sol";
import {IBurveMultiSimplex} from "../multi/interfaces/IBurveMultiSimplex.sol";
import {IBurveMultiValue} from "../multi/interfaces/IBurveMultiValue.sol";
import {AdminLib} from "Commons/Util/Admin.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Auto165} from "Commons/ERC/Auto165.sol";

contract Rewarder is RFTPayer, Auto165 {
    IBurveMultiSimplex public immutable pool;
    IAdjustor public immutable adjustor;

    address[] public rewardTokens;
    mapping(address token => bool) isRewardToken;
    mapping(address rewardT => mapping(address inputT => uint128 rateX64))
        public rewardRates;

    constructor(address _pool) RFTPayer() {
        AdminLib.initOwner(msg.sender);
        pool = IBurveMultiSimplex(_pool);
        adjustor = IAdjustor(pool.getAdjustor());
    }

    function fund(
        address inputToken,
        address rewardToken,
        uint128 rateX64,
        uint256 amount
    ) external {
        AdminLib.validateOwner();

        if (!isRewardToken[rewardToken]) {
            isRewardToken[rewardToken] = true;
            rewardTokens.push(rewardToken);
        }

        rewardRates[rewardToken][inputToken] = rateX64;

        address[] memory tokens = new address[](1);
        tokens[0] = rewardToken;
        int256[] memory deltas = new int256[](1);
        deltas[0] = int256(amount);

        RFTLib.settle(msg.sender, tokens, deltas, "");
    }

    function withdraw(address rewardToken, uint256 amount) external {
        AdminLib.validateOwner();

        address[] memory tokens = new address[](1);
        tokens[0] = rewardToken;
        int256[] memory deltas = new int256[](1);
        deltas[0] = -int256(amount);

        RFTLib.settle(msg.sender, tokens, deltas, "");
    }

    function viewRewards(
        address owner,
        uint16 closureId
    ) external view returns (int256[] memory bonuses) {
        (, , uint256[16] memory earnings, ) = IBurveMultiValue(address(pool))
            .queryValue(owner, closureId);

        address[] memory tokens = pool.getTokens();
        bonuses = new int256[](rewardTokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 nominal = adjustor.toNominal(tokens[i], earnings[i], false);

            reward(tokens[i], nominal, bonuses);
        }

        for (uint256 i = 0; i < bonuses.length; ++i) {
            uint256 balance = IERC20(rewardTokens[i]).balanceOf(address(this)); // Ensure the contract has enough
            if (balance < uint256(bonuses[i])) {
                bonuses[i] = int256(balance);
            }
        }
    }

    function getRewardTokens()
        public
        view
        returns (address[] memory _rewardTokens)
    {
        _rewardTokens = new address[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; ++i)
            _rewardTokens[i] = rewardTokens[i];
    }

    function reward(
        address token,
        uint256 nominal,
        int256[] memory bonuses
    ) internal view {
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            uint128 rateX64 = rewardRates[rewardToken][token];

            if (rateX64 > 0 && nominal > 0) {
                // Calculate the bonus for this token.
                uint256 bonus = (rateX64 * nominal) >> 64;
                bonuses[i] += int256(bonus);
            }
        }
    }

    function tokenRequestCB(
        address[] calldata tokens,
        int256[] calldata requests,
        bytes calldata data
    ) external returns (bytes memory) {
        require(msg.sender == address(pool), "Unauthorized");

        require(data.length > 0, "Invalid data");
        (address recipient, uint16 closureId) = abi.decode(
            data,
            (address, uint16)
        );

        address[] memory _rewardTokens = getRewardTokens();
        int256[] memory bonuses = new int256[](_rewardTokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            require(requests[i] <= 0, "Invalid request amount");
            uint256 nominal = adjustor.toNominal(
                tokens[i],
                uint256(-requests[i]),
                false
            );

            reward(tokens[i], nominal, bonuses);
        }

        for (uint256 i = 0; i < bonuses.length; ++i) {
            uint256 balance = IERC20(_rewardTokens[i]).balanceOf(address(this)); // Ensure the contract has enough
            if (balance < uint256(bonuses[i])) {
                bonuses[i] = int256(balance);
            }
            bonuses[i] = -bonuses[i]; // Convert bonuses to negative values for settlement
        }

        RFTLib.settle(recipient, _rewardTokens, bonuses, "");
        RFTLib.settle(recipient, tokens, requests, "");
    }
}
