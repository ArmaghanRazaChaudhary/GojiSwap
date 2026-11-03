// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.1;

/******************* Imports **********************/
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";


/// @title A time locking smart contract
/// @author M.Armaghan Raza
/// @notice User's can use this contract for locking ERC20 based only supported tokens for either 3, 6, 9 or 12 months.
/// @dev All function calls are currently implemented without side effects.
/// @custom:experimental This contract is experimental.
contract ERC20Locker is Ownable, ReentrancyGuard {

    /******************* State Variables **********************/
    /// @notice This struct stores information regarding locked tokens.
    struct LockedRecords {
        uint256 amount;
        uint256 validity;
        address payable addr;
        address token;
        bool doesExist;
        uint256 insertedAt;
        uint256 updatedAt;
    }

    /// @notice This struct shall contain address of admin who added the token and a bool for temorarily enabling and disabling support for the token.
    struct SupportedToken {
        address token;
        address added_by;
        bool enabled;
        uint256 insertedAt;
        uint256 updatedAt;
    }

    /// @notice Mapping for storing supported tokens information.
    mapping (address => SupportedToken) private supportedTokens;

    /// @notice Following is a mapping where we map every locked token's information against a unique number.
    mapping (address => mapping(address => LockedRecords)) private userLockRecords;

    /******************* Events **********************/
    event Locked(
        address indexed _of,
        uint256 _amount,
        address token,
        uint256 _validity
    );

    event Unlocked(
        address indexed _of,
        uint256 _amount,
        address token,
        uint256 timestamp
    );

    /******************* Modifiers **********************/
    modifier ValidateLockParams (uint256 _amount, uint256 _time) {
        require (_amount > 0, "Amount should be greater than zero");
        require (_time == 3 || _time == 6 || _time == 9 || _time == 12, "Please enter a digit as 3, 6, 9 or 12");
        require(address(msg.sender).balance >= _amount, "Amount to be locked exceeds total balance!");
        _;
    }

    modifier isContract(address token) {
        uint256 size;
        assembly {
            size := extcodesize(token)
        }
        require(size > 0, "Please provide valid token address!!!");
        _;
    }

    modifier ValidateUserBalance (address _token, uint256 _amount) {
        IERC20 token = IERC20(_token);
        require(token.balanceOf(msg.sender) > _amount, "Insufficient balance");
        _;
    }

    modifier IsSupportedToken (address _token) {
        require(supportedTokens[_token].token == _token && supportedTokens[_token].enabled, "Address of token provided is not supported!");
        _;
    }

    modifier HasUserAlreadyLockedSameToken (address _token) {
        require(!userLockRecords[msg.sender][_token].doesExist, "You've already locked this token, please unlock them all before locking again.");
        _;
    }

    modifier IsTokenAdded (address _token) {
        require(supportedTokens[_token].token == _token, "Added of token doesnot exist in supported tokens, please use addSupportedToken method for adding this token.");
        _;
    }

    modifier IsNewToken (address _token) {
        require(supportedTokens[_token].token != _token, "Token is already added as supported token!");
        _;
    }

    modifier IsTokenEnabled (address _token) {
        require(supportedTokens[_token].enabled, "Token already disabled");
        _;
    }

    modifier IsTokenDisabled (address _token) {
        require(!supportedTokens[_token].enabled, "Token already enabled");
        _;
    }


    /******************* Admin Methods **********************/
    /// @notice Admin method to add new supported token
    /// @param _token Address of token to be added as supported token
    function addSupportedToken (address _token) public onlyOwner isContract(_token) IsNewToken(_token) {
        supportedTokens[_token] = SupportedToken(_token, msg.sender, true, block.timestamp, 0);
    }

    /// @notice Admin method to diable an already added supported token
    /// @param _token Address of token to be disabled
    function disableSupportedToken (address _token) public onlyOwner IsTokenAdded(_token) IsTokenEnabled(_token) {
        supportedTokens[_token].enabled = false;
        supportedTokens[_token].updatedAt = block.timestamp;
    }

    /// @notice Admin method to enable an already added but disabled supported token
    /// @param _token Address of token to be enabled
    function enableSupportedToken (address _token) public onlyOwner IsTokenAdded(_token) IsTokenDisabled(_token) {
        supportedTokens[_token].enabled = true;
        supportedTokens[_token].updatedAt = block.timestamp;
    }

    /******************* Private Methods **********************/
    /// @notice This private method transfers `_amount` from user's account to this contract for locking purpose
    /// @param _token Addess of user's ERC20 based token smart contract
    /// @param _amount Amount of tokens/funds user wishes to lock
    /// @param validUntil Amount of time for which user wishes to lock their funds.
    function lockUserFunds (address _token, uint _amount, uint validUntil) private nonReentrant {
        IERC20 token = IERC20(_token);
        token.transferFrom(msg.sender, address(this), _amount);
        userLockRecords[msg.sender][_token] = LockedRecords(_amount, validUntil, payable(msg.sender), _token, true, block.timestamp, 0);
        
        emit Locked(msg.sender, _amount, _token, validUntil);
    }


    /******************* Public Methods **********************/
    /// @notice This method locks `_amount` token(s) for `_time` months
    /// @dev Validate if prodvided `_token` is a supported token before locking
    /// @param _token Address of token that user wants to lock.
    /// @param _amount Number of token to be locked.
    /// @param _time Number of months for locking `_amount` token(s).
    function lock (address _token, uint256 _amount, uint256 _time) public payable isContract(_token)
      ValidateLockParams(_amount, _time) IsSupportedToken(_token) 
      ValidateUserBalance(_token, _amount) HasUserAlreadyLockedSameToken(_token) {        
        /// @notice Please uncomment this line and comment out next line when need to be locked for `_time` months.
        uint256 validUntil =  (_time * 30 days) + block.timestamp;
        // uint256 validUntil =  (_time * 1 minutes) + block.timestamp; // For testing purpose, please comment this line.
        // Following call to private method solves, stack too deep compile time error.
        lockUserFunds(_token, _amount, validUntil);
    }

    /// @notice This method unlock user's all tokens for a given address
    /// @param _token Address of token to be unlocked
    function unlockAll (address _token) public nonReentrant {
        if (userLockRecords[msg.sender][_token].addr == msg.sender && userLockRecords[msg.sender][_token].token == _token) {
            if (userLockRecords[msg.sender][_token].validity < block.timestamp) {
                IERC20 token = IERC20(_token);
                token.transfer(msg.sender, userLockRecords[msg.sender][_token].amount);

                delete userLockRecords[msg.sender][_token];

                emit Unlocked(
                    msg.sender, userLockRecords[msg.sender][_token].amount,
                    _token, block.timestamp
                );

            } else {
                revert("You can not unlock funds right now!");
            }
        } else {
            revert("You do not have any funds locked for the provided token address!");
        }
    }

    /// @notice This method unlock `_amount` tokens for a given token address
    /// @param _token Address of token to be unlocked
    /// @param _amount Amount of tokens to be unlocked
    function unlock (address _token, uint256 _amount) public nonReentrant {
        if (userLockRecords[msg.sender][_token].addr == msg.sender && userLockRecords[msg.sender][_token].token == _token) {
            if (userLockRecords[msg.sender][_token].validity <= block.timestamp) {
                if (userLockRecords[msg.sender][_token].amount >= _amount) {
                    uint remainingBalance = userLockRecords[msg.sender][_token].amount - _amount;  

                    if (remainingBalance == 0) delete userLockRecords[msg.sender][_token];
                    else userLockRecords[msg.sender][_token].amount = remainingBalance;

                    IERC20 token = IERC20(_token);
                    token.transfer(msg.sender, _amount);

                    emit Unlocked(msg.sender, _amount, _token, block.timestamp);
                } else {
                    revert(
                        string (
                            abi.encodePacked (
                                "Amount you want to unlock exceeds your balance by ",
                                _amount - userLockRecords[msg.sender][_token].amount,
                                " tokens."
                            )
                        )
                    );
                }
            } else {
                revert("You can not unlock funds right now!");
            }
        } else {
            revert("You do not have any funds locked for the provided token address!");
        }
    }

    function checkFunds (address _token) public view returns (uint256) {
        return userLockRecords[msg.sender][_token].amount;
    }

}
