// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @title DummyRewarder - A test contract that counts onDeposit and onWithdraw calls
/// @notice This contract is used for testing the BRC20 rewarder integration
contract DummyRewarder {
    // Counters for tracking calls
    uint256 public depositCallCount;
    uint256 public withdrawCallCount;
    
    // Track total amounts
    uint256 public totalDepositAmount;
    uint256 public totalWithdrawAmount;
    
    // Track calls per user
    mapping(address => uint256) public userDepositCount;
    mapping(address => uint256) public userWithdrawCount;
    mapping(address => uint256) public userDepositAmount;
    mapping(address => uint256) public userWithdrawAmount;
    
    // Track all calls for verification
    struct CallRecord {
        address user;
        uint256 amount;
        uint256 timestamp;
        bool isDeposit;
    }
    
    CallRecord[] public allCalls;
    
    // Events
    event DepositCalled(address indexed user, uint256 amount);
    event WithdrawCalled(address indexed user, uint256 amount);
    
    /// @notice Called by BRC20 when shares are minted
    function onDeposit(address user, uint256 mintedShares) external {
        depositCallCount++;
        totalDepositAmount += mintedShares;
        userDepositCount[user]++;
        userDepositAmount[user] += mintedShares;
        
        allCalls.push(CallRecord({
            user: user,
            amount: mintedShares,
            timestamp: block.timestamp,
            isDeposit: true
        }));
        
        emit DepositCalled(user, mintedShares);
    }
    
    /// @notice Called by BRC20 when shares are burned
    function onWithdraw(address user, uint256 requestedSharesToBurn) external {
        withdrawCallCount++;
        totalWithdrawAmount += requestedSharesToBurn;
        userWithdrawCount[user]++;
        userWithdrawAmount[user] += requestedSharesToBurn;
        
        allCalls.push(CallRecord({
            user: user,
            amount: requestedSharesToBurn,
            timestamp: block.timestamp,
            isDeposit: false
        }));
        
        emit WithdrawCalled(user, requestedSharesToBurn);
    }
    
    /// @notice Get total call count
    function getTotalCallCount() external view returns (uint256) {
        return depositCallCount + withdrawCallCount;
    }
    
    /// @notice Get call count for a specific user
    function getUserCallCount(address user) external view returns (uint256 depositCount, uint256 withdrawCount) {
        return (userDepositCount[user], userWithdrawCount[user]);
    }
    
    /// @notice Get total amounts for a specific user
    function getUserAmounts(address user) external view returns (uint256 depositAmount, uint256 withdrawAmount) {
        return (userDepositAmount[user], userWithdrawAmount[user]);
    }
    
    /// @notice Get all calls made to this contract
    function getAllCalls() external view returns (CallRecord[] memory) {
        return allCalls;
    }
    
    /// @notice Get calls for a specific user
    function getUserCalls(address user) external view returns (CallRecord[] memory) {
        uint256 userCallCount = userDepositCount[user] + userWithdrawCount[user];
        CallRecord[] memory userCalls = new CallRecord[](userCallCount);
        
        uint256 index = 0;
        for (uint256 i = 0; i < allCalls.length; i++) {
            if (allCalls[i].user == user) {
                userCalls[index] = allCalls[i];
                index++;
            }
        }
        
        return userCalls;
    }
    
    /// @notice Reset all counters (for testing)
    function reset() external {
        depositCallCount = 0;
        withdrawCallCount = 0;
        totalDepositAmount = 0;
        totalWithdrawAmount = 0;
        
        // Clear user mappings
        for (uint256 i = 0; i < allCalls.length; i++) {
            address user = allCalls[i].user;
            userDepositCount[user] = 0;
            userWithdrawCount[user] = 0;
            userDepositAmount[user] = 0;
            userWithdrawAmount[user] = 0;
        }
        
        delete allCalls;
    }
}
