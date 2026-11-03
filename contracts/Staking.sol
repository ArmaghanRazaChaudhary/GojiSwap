// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RewardPool} from "./RewardPool.sol";

/// @title Staking
/// @author M. Armaghan Raza
/// @notice Stake a token and earn rewards paid in the same token.
contract Staking is RewardPool {
    /// @notice Open a staking pool for `token`. Rewards are paid in `token` too.
    function addToken(address token) external onlyOwner {
        _addPool(token, token);
    }
}
