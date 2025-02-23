// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/***
    @notice Station Proxy manages BGT earning and allocation for all of Burve and Burve integrated products.

    Burve protocols typically interact with two LP Tokens: 1. The LP token it issues 2. LP Tokens issued to it
    from protocols it uses.
    The protocols send the second type of LP tokens to the station proxy so it can earn BGT on its behalf.

    Protocols do not receive back the earnings from the LP tokens it gives to station proxy directly.
    They are instead claimed by the user from the station proxy. This is why LP tokens should be ascribed an owner,
    indicating who can claim the rewards from those LP tokens.

    Exactly how the station proxy directs rewards and BGT earnings is complex and subject to governance.
***/
interface IStationProxy {
    /// Called by a user to harvest rewards owed to them from lptoken deposits they own.
    function harvest() external;

    /// Called by a burve protocol to deposit LPtokens on behalf of a owner and accrue rewards for them.
    /// @param lpToken The token being deposited
    /// @param amount The amount of token to be deposited
    /// @param owner Who "owns" the lp tokens and who the rewards earned by the lpToken should be claimable by.
    function depositLP(address lpToken, uint256 amount, address owner) external;

    /// Called by a burve protocol to withdraw lptokens on behalf of a owner.
    /// @param lpToken The token being withdrawn
    /// @param amount The amount of token to be withdrawn
    /// @param owner Which owners account we should withdraw these lp tokens from.
    function withdrawLP(
        address lpToken,
        uint256 amount,
        address owner
    ) external;

    /// Moves existing deposits to a new station proxy.
    function migrate(IStationProxy newStationProxy) external;
}
