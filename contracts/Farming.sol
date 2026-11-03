// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RewardPool} from "./RewardPool.sol";

/// @title Farming
/// @author M. Armaghan Raza
/// @notice Deposit LP tokens and earn rewards paid in a separate reward token.
contract Farming is RewardPool {
    /// @notice Open a farm for `lpToken` that pays out in `rewardToken`.
    function addPool(address lpToken, address rewardToken) external onlyOwner {
        _addPool(lpToken, rewardToken);
    }
}
