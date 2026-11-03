// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ERC20Locker
/// @author M. Armaghan Raza
/// @notice Lock a supported ERC20 token for 3, 6, 9 or 12 months. One lock per user per token.
contract ERC20Locker is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MONTH = 30 days;

    struct Lock {
        uint256 amount;
        uint256 unlockAt;
    }

    /// @notice token => accepted for new locks (existing locks can always be withdrawn)
    mapping(address => bool) public supported;

    /// @notice token => has ever been added
    mapping(address => bool) public listed;

    /// @notice user => token => lock
    mapping(address => mapping(address => Lock)) public locks;

    event TokenAdded(address indexed token);
    event TokenEnabled(address indexed token, bool enabled);
    event Locked(address indexed user, address indexed token, uint256 amount, uint256 unlockAt);
    event Unlocked(address indexed user, address indexed token, uint256 amount);

    error NotAContract(address token);
    error AlreadyListed(address token);
    error NotListed(address token);
    error NotSupported(address token);
    error ZeroAmount();
    error InvalidDuration(uint256 months);
    error AlreadyLocked();
    error NoLock();
    error StillLocked(uint256 unlockAt);
    error ExceedsLocked(uint256 requested, uint256 locked);

    constructor() Ownable(msg.sender) {}

    /******************* Admin **********************/

    function addSupportedToken(address token) external onlyOwner {
        if (token.code.length == 0) revert NotAContract(token);
        if (listed[token]) revert AlreadyListed(token);
        listed[token] = true;
        supported[token] = true;
        emit TokenAdded(token);
    }

    /// @notice Pause or resume new locks for `token`. Unlocking is never blocked.
    function setTokenEnabled(address token, bool enabled) external onlyOwner {
        if (!listed[token]) revert NotListed(token);
        supported[token] = enabled;
        emit TokenEnabled(token, enabled);
    }

    /******************* User **********************/

    /// @notice Lock `amount` of `token` for `months` (3, 6, 9 or 12).
    function lock(address token, uint256 amount, uint256 months) external nonReentrant {
        if (!supported[token]) revert NotSupported(token);
        if (amount == 0) revert ZeroAmount();
        if (months != 3 && months != 6 && months != 9 && months != 12) revert InvalidDuration(months);
        if (locks[msg.sender][token].amount != 0) revert AlreadyLocked();

        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - before;

        uint256 unlockAt = block.timestamp + months * MONTH;
        locks[msg.sender][token] = Lock(received, unlockAt);
        emit Locked(msg.sender, token, received, unlockAt);
    }

    /// @notice Withdraw `amount` once the lock has expired.
    function unlock(address token, uint256 amount) public nonReentrant {
        Lock storage l = locks[msg.sender][token];
        if (l.amount == 0) revert NoLock();
        if (block.timestamp < l.unlockAt) revert StillLocked(l.unlockAt);
        if (amount == 0) revert ZeroAmount();
        if (amount > l.amount) revert ExceedsLocked(amount, l.amount);

        l.amount -= amount;
        if (l.amount == 0) delete locks[msg.sender][token];

        IERC20(token).safeTransfer(msg.sender, amount);
        emit Unlocked(msg.sender, token, amount);
    }

    /// @notice Withdraw the whole lock once it has expired.
    function unlockAll(address token) external {
        unlock(token, locks[msg.sender][token].amount);
    }
}
