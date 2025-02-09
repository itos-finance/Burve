// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface IBGTStationProxy {
    /// Query which liquid bgt you should expect to get from this proxy.
    function liquidBGT() external view returns (address liquidBGTWrapper);

    // Deposit LP tokens and get back the amount of BGT currently owed to msg.sender.
    function deposit(
        address lpToken,
        uint256 amount
    ) external returns (uint256 bgtBalance);

    /// ONLY withdraws the LP token.
    function withdrawLPToken(
        address lpToken,
        uint256 amount
    ) external returns (uint256 outAmount);

    /// Withdraws the BGT allocation calculated from checkpoints.
    function withdrawBGT(uint256 amount) external returns (uint256 outAmount);

    /// Withdraws the reward token specified.
    function withdrawReward(
        address token,
        uint256 amount
    ) external returns (uint256 outAmount);

    /// Query the balance of a given reward token owed to an address.
    function queryRewardBalance(
        address owner,
        address token
    ) external view returns (uint256 balance);

    /// Query the total BGT owed to owner
    function queryBGTBalance(
        address owner
    ) external view returns (uint256 balance);

    function migrateBGT(address previousLiquidBGT, uint256 bgtAmount);
}
