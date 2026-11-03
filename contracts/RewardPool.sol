// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title RewardPool
/// @author M. Armaghan Raza
/// @notice Shared logic behind Staking and Farming. Users deposit a token, the owner
///         funds rewards, and every depositor earns a share in proportion to their deposit.
/// @dev Uses a cumulative reward-per-share accumulator, so distribute() costs the same
///      no matter how many users there are. One pool per deposit token.
abstract contract RewardPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e18;

    struct Pool {
        IERC20 rewardToken;
        bool exists;
        bool enabled; // disabled pools take no new deposits or rewards; withdraw and claim always work
        uint256 totalDeposited;
        uint256 accRewardPerShare; // total reward per deposited token since the start, scaled by PRECISION
    }

    struct UserInfo {
        uint256 amount; // this user's deposit
        uint256 rewardPerSharePaid; // accumulator value at this user's last update
        uint256 pending; // earned but not yet claimed
    }

    /// @notice deposit token => pool
    mapping(address => Pool) public pools;

    /// @notice deposit token => user => position
    mapping(address => mapping(address => UserInfo)) public users;

    /// @notice reward token => rewards funded but not yet claimed (cannot be withdrawn by the owner)
    mapping(address => uint256) public reservedRewards;

    event PoolAdded(address indexed token, address indexed rewardToken);
    event PoolEnabled(address indexed token, bool enabled);
    event Deposited(address indexed token, address indexed user, uint256 amount);
    event Withdrawn(address indexed token, address indexed user, uint256 amount);
    event RewardDistributed(address indexed token, uint256 amount);
    event RewardClaimed(address indexed token, address indexed user, address indexed receiver, uint256 amount);
    event ExcessWithdrawn(address indexed token, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error PoolExists();
    error PoolNotFound();
    error PoolDisabled();
    error NoDepositors();
    error InsufficientDeposit(uint256 requested, uint256 available);
    error ExceedsExcess(uint256 requested, uint256 available);

    constructor() Ownable(msg.sender) {}

    /******************* Admin **********************/

    /// @notice Turn a pool on or off. Users can always withdraw and claim from a disabled pool.
    function setPoolEnabled(address token, bool enabled) external onlyOwner {
        _pool(token).enabled = enabled;
        emit PoolEnabled(token, enabled);
    }

    /// @notice Fund `amount` reward tokens and split them across current depositors of `token`.
    /// @dev The rewards are pulled in here, so every reward is backed by real tokens.
    function distribute(address token, uint256 amount) external onlyOwner nonReentrant {
        Pool storage pool = _pool(token);
        if (!pool.enabled) revert PoolDisabled();
        if (amount == 0) revert ZeroAmount();
        if (pool.totalDeposited == 0) revert NoDepositors();

        uint256 received = _pull(pool.rewardToken, amount);
        pool.accRewardPerShare += (received * PRECISION) / pool.totalDeposited;
        reservedRewards[address(pool.rewardToken)] += received;
        emit RewardDistributed(token, received);
    }

    /// @notice Recover tokens sent here by mistake. Deposits and unclaimed rewards are off limits.
    function withdrawExcess(address token, uint256 amount) external onlyOwner nonReentrant {
        uint256 available = excessOf(token);
        if (amount > available) revert ExceedsExcess(amount, available);
        IERC20(token).safeTransfer(msg.sender, amount);
        emit ExcessWithdrawn(token, amount);
    }

    /******************* User **********************/

    function deposit(address token, uint256 amount) external nonReentrant {
        Pool storage pool = _pool(token);
        if (!pool.enabled) revert PoolDisabled();
        if (amount == 0) revert ZeroAmount();

        _accrue(pool, users[token][msg.sender]);
        uint256 received = _pull(IERC20(token), amount);
        users[token][msg.sender].amount += received;
        pool.totalDeposited += received;
        emit Deposited(token, msg.sender, received);
    }

    function withdraw(address token, uint256 amount) external nonReentrant {
        Pool storage pool = _pool(token);
        UserInfo storage user = users[token][msg.sender];
        if (amount == 0) revert ZeroAmount();
        if (amount > user.amount) revert InsufficientDeposit(amount, user.amount);

        _accrue(pool, user);
        user.amount -= amount;
        pool.totalDeposited -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdrawn(token, msg.sender, amount);
    }

    /// @notice Claim rewards earned on `token`. `receiver` 0 means pay the caller.
    function claim(address token, address receiver) external nonReentrant returns (uint256 amount) {
        Pool storage pool = _pool(token);
        UserInfo storage user = users[token][msg.sender];

        _accrue(pool, user);
        amount = user.pending;
        if (amount == 0) return 0;

        user.pending = 0;
        reservedRewards[address(pool.rewardToken)] -= amount;
        address to = receiver == address(0) ? msg.sender : receiver;
        pool.rewardToken.safeTransfer(to, amount);
        emit RewardClaimed(token, msg.sender, to, amount);
    }

    /******************* Views **********************/

    function pendingReward(address token, address account) external view returns (uint256) {
        Pool storage pool = pools[token];
        UserInfo storage user = users[token][account];
        return user.pending + (user.amount * (pool.accRewardPerShare - user.rewardPerSharePaid)) / PRECISION;
    }

    /// @notice Balance of `token` that is neither a deposit nor a reserved reward.
    function excessOf(address token) public view returns (uint256) {
        uint256 locked = pools[token].totalDeposited + reservedRewards[token];
        uint256 balance = IERC20(token).balanceOf(address(this));
        return balance > locked ? balance - locked : 0;
    }

    /******************* Internal **********************/

    function _addPool(address token, address rewardToken) internal {
        if (token == address(0) || rewardToken == address(0)) revert ZeroAddress();
        if (pools[token].exists) revert PoolExists();
        pools[token] = Pool({
            rewardToken: IERC20(rewardToken),
            exists: true,
            enabled: true,
            totalDeposited: 0,
            accRewardPerShare: 0
        });
        emit PoolAdded(token, rewardToken);
    }

    function _pool(address token) internal view returns (Pool storage pool) {
        pool = pools[token];
        if (!pool.exists) revert PoolNotFound();
    }

    /// @dev Move everything earned so far into `pending` before the user's deposit changes.
    function _accrue(Pool storage pool, UserInfo storage user) private {
        user.pending += (user.amount * (pool.accRewardPerShare - user.rewardPerSharePaid)) / PRECISION;
        user.rewardPerSharePaid = pool.accRewardPerShare;
    }

    /// @dev Pull tokens in and return what actually arrived (handles fee-on-transfer tokens).
    function _pull(IERC20 token, uint256 amount) private returns (uint256) {
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        return token.balanceOf(address(this)) - before;
    }
}
